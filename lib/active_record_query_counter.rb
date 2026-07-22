# frozen_string_literal: true

require "securerandom"

require_relative "active_record_query_counter/connection_adapter_extension"
require_relative "active_record_query_counter/counter"
require_relative "active_record_query_counter/thresholds"
require_relative "active_record_query_counter/transaction_info"
require_relative "active_record_query_counter/transaction_extension"

# Everything you need to count ActiveRecord queries and row counts within a block.
#
# @example
#
#  ActiveRecordQueryCounter.count_queries do
#    yield
#    puts ActiveRecordQueryCounter.query_count
#    puts ActiveRecordQueryCounter.row_count
#  end
module ActiveRecordQueryCounter
  VERSION = File.read(File.join(__dir__, "..", "VERSION")).strip

  autoload :RackMiddleware, "active_record_query_counter/rack_middleware"
  autoload :SidekiqMiddleware, "active_record_query_counter/sidekiq_middleware"

  IGNORED_STATEMENTS = %w[SCHEMA EXPLAIN].freeze
  private_constant :IGNORED_STATEMENTS

  @lock = Mutex.new
  @default_thresholds = Thresholds.new

  class << self
    # Enable query counting within a block.
    #
    # @return [Object] the result of the block
    def count_queries
      save_counter = current_counter
      begin
        counter = Counter.new
        self.current_counter = counter

        retval = yield

        transaction_count = counter.transaction_count
        if transaction_count > 0
          transaction_threshold = counter.thresholds.transaction_count || -1
          if transaction_threshold.between?(0, transaction_count)
            send_notification("transaction_count", counter.first_transaction_start_time, counter.last_transaction_end_time, transactions: counter.transactions)
          end
        end

        retval
      ensure
        self.current_counter = save_counter
      end
    end

    # Disable query counting in a block. Any queries or transactions inside the block will not
    # be counted.
    #
    # @return [Object] the return value of the block
    def disable(&block)
      counter = current_counter
      begin
        self.current_counter = nil
        yield
      ensure
        self.current_counter = counter
      end
    end

    # Increment the query counters.
    #
    # The reported query time is the wall clock time spent executing the query with the GC
    # time, Ruby thread CPU time, and connection setup time subtracted out so that it reflects
    # the time actually spent waiting on the database as closely as possible (see
    # {.database_query_time}). This query time, rather than the raw wall clock time, is what is
    # accumulated, compared against the threshold, and used as the duration of the emitted
    # notification.
    #
    # @param sql [String] the SQL statement that was executed
    # @param name [String, nil] the name of the query
    # @param binds [Array] the bind parameters
    # @param row_count [Integer] the number of rows returned by the query
    # @param start_time [Float] the monotonic time when the query started
    # @param end_time [Float] the monotonic time when the query ended
    # @param gc_time [Float] the GC time in seconds that elapsed while the query ran
    # @param cpu_time [Float] the thread CPU time in seconds spent while the query ran
    # @param connection_time [Float] the time in seconds spent establishing, verifying, or
    #   reconnecting the database connection while the query ran
    # @return [void]
    # @api private
    def add_query(sql, name, binds, row_count, start_time, end_time, gc_time, cpu_time, connection_time = 0.0)
      return if IGNORED_STATEMENTS.include?(name)

      counter = current_counter
      return unless counter.is_a?(Counter)

      elapsed_time = end_time - start_time
      query_time = database_query_time(elapsed_time, gc_time, cpu_time, connection_time)
      counter.query_count += 1
      counter.row_count += row_count
      counter.query_time += query_time

      # The notification duration is the database query time, so the event ends that long after
      # it started rather than at the raw wall clock end time.
      notification_end_time = start_time + query_time

      trace = nil
      query_time_threshold = counter.thresholds.query_time || -1
      if query_time_threshold.between?(0, query_time)
        trace = backtrace
        payload = notification_payload(sql: sql, binds: binds, row_count: row_count, trace: trace, elapsed_time: elapsed_time, gc_time: gc_time, cpu_time: cpu_time, connection_time: connection_time)
        send_notification("query_time", start_time, notification_end_time, **payload)
      end

      row_count_threshold = counter.thresholds.row_count || -1
      if row_count_threshold.between?(0, row_count)
        trace ||= backtrace
        payload = notification_payload(sql: sql, binds: binds, row_count: row_count, trace: trace, elapsed_time: elapsed_time, gc_time: gc_time, cpu_time: cpu_time, connection_time: connection_time)
        send_notification("row_count", start_time, notification_end_time, **payload)
      end
    end

    # Increment the transaction counters.
    #
    # @param start_time [Float] the time the transaction started
    # @param end_time [Float] the time the transaction ended
    # @return [void]
    # @api private
    def add_transaction(start_time, end_time)
      counter = current_counter
      return unless counter.is_a?(Counter)

      trace = backtrace
      counter.add_transaction(trace: trace, start_time: start_time, end_time: end_time)

      transaction_time_threshold = counter.thresholds.transaction_time || -1
      if transaction_time_threshold.between?(0, end_time - start_time)
        send_notification("transaction_time", start_time, end_time, trace: backtrace)
      end
    end

    # Return the number of rollbacks that have been counted within the current block.
    # Returns nil if not inside a block where queries are being counted.
    #
    # @return [Integer, nil]
    def increment_rollbacks
      counter = current_counter
      return unless counter.is_a?(Counter)

      counter.rollback_count += 1
    end

    # Begin measuring the time spent establishing, verifying, or reconnecting the database
    # connection for a single query. Returns the timer that was previously in effect so it can
    # be restored by {.stop_connection_timer}; this keeps nested queries (should they ever
    # occur) from leaking connection time into one another.
    #
    # @return [Object, nil] the previous connection timer
    # @api private
    def start_connection_timer
      previous_timer = connection_timer
      self.connection_timer = {elapsed: 0.0, measuring: false}
      previous_timer
    end

    # Finish measuring connection setup time for the current query and restore the previously
    # active timer.
    #
    # @param previous_timer [Object, nil] the timer returned by {.start_connection_timer}
    # @return [Float] the connection setup time in seconds accumulated for the query
    # @api private
    def stop_connection_timer(previous_timer)
      timer = connection_timer
      self.connection_timer = previous_timer
      timer ? timer[:elapsed] : 0.0
    end

    # Measure the wall clock time a connection setup operation (connect, reconnect, or verify)
    # takes and accumulate it onto the current query's connection timer. When no query is being
    # measured, or when a connection setup operation is already being measured (for example when
    # `verify!` delegates to `reconnect!`), the block is yielded without recording so the
    # interval is only counted once.
    #
    # @yield the connection setup operation
    # @return [Object] the result of the block
    # @api private
    def measure_connection_setup
      timer = connection_timer
      return yield if timer.nil? || timer[:measuring]

      timer[:measuring] = true
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        yield
      ensure
        timer[:elapsed] += Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        timer[:measuring] = false
      end
    end

    # Return the number of queries that have been counted within the current block.
    # Returns nil if not inside a block where queries are being counted.
    #
    # @return [Integer, nil]
    def query_count
      counter = current_counter
      counter.query_count if counter.is_a?(Counter)
    end

    # Return the number of queries that hit the query cache and were not sent to the database
    # that have been counted within the current block.  Returns nil if not inside a block where
    # queries are being counted.
    #
    # @return [Integer, nil]
    def cached_query_count
      counter = current_counter
      counter.cached_query_count if counter.is_a?(Counter)
    end

    # Return the number of rows that have been counted within the current block.
    # Returns nil if not inside a block where queries are being counted.
    #
    # @return [Integer, nil]
    def row_count
      counter = current_counter
      counter.row_count if counter.is_a?(Counter)
    end

    # Return the total time spent executing queries within the current block.
    # Returns nil if not inside a block where queries are being counted.
    #
    # @return [Float, nil]
    def query_time
      counter = current_counter
      counter.query_time if counter.is_a?(Counter)
    end

    # Return the number of transactions that have been counted within the current block.
    # Returns nil if not inside a block where queries are being counted.
    #
    # @return [Integer, nil]
    def transaction_count
      counter = current_counter
      counter.transaction_count if counter.is_a?(Counter)
    end

    # Return the total time spent in transactions that have been counted within the current block.
    # Returns nil if not inside a block where queries are being counted.
    #
    # @return [Float, nil]
    def transaction_time
      counter = current_counter
      counter.transaction_time if counter.is_a?(Counter)
    end

    # Return the time when the first transaction began within the current block.
    # Returns nil if not inside a block where queries are being counted or there are no transactions.
    #
    # @return [Float, nil] the monotonic time when the first transaction began,
    def first_transaction_start_time
      counter = current_counter
      counter.first_transaction_start_time if counter.is_a?(Counter)
    end

    # Return the time when the last transaction ended within the current block.
    # Returns nil if not inside a block where queries are being counted or there are no transactions.
    #
    # @return [Float, nil] the monotonic time when the last transaction ended,
    def last_transaction_end_time
      counter = current_counter
      counter.last_transaction_end_time if counter.is_a?(Counter)
    end

    # Return an array of transaction information for any transactions that have been counted
    # within the current block. Returns nil if not inside a block where queries are being counted.
    #
    # @return [Array<ActiveRecordQueryCounter::TransactionInfo>, nil]
    def transactions
      counter = current_counter
      counter.transactions if counter.is_a?(Counter)
    end

    # Return the number of transactions that have rolled back within the current block.
    # Returns nil if not inside a block where queries are being counted.
    #
    # @return [Integer, nil]
    def rollback_count
      counter = current_counter
      counter.rollback_count if counter.is_a?(Counter)
    end

    # Return the query info as a hash with keys :query_count, :row_count, :query_time
    # :transaction_count, and :transaction_type or nil if not inside a block where queries
    # are being counted.
    #
    # @return [Hash, nil]
    def info
      counter = current_counter
      if counter.is_a?(Counter)
        {
          query_count: counter.query_count,
          row_count: counter.row_count,
          query_time: counter.query_time,
          cached_query_count: counter.cached_query_count,
          cache_hit_rate: counter.cache_hit_rate,
          transaction_count: counter.transaction_count,
          transaction_time: counter.transaction_time,
          rollback_count: counter.rollback_count
        }
      end
    end

    # The global notification thresholds for sending notifications. The values set in these
    # thresholds are used as the default values.
    #
    # @return [ActiveRecordQueryCounter::Thresholds]
    attr_reader :default_thresholds

    # Get the current local notification thresholds. These thresholds are only used within
    # the current `count_queries` block.
    def thresholds
      current_counter&.thresholds || default_thresholds.dup
    end

    # Enable the query counting behavior on a connection adapter class.
    #
    # @param connection_class [Class] the connection adapter class to extend
    # @return [void]
    def enable!(connection_class)
      ActiveSupport.on_load(:active_record) do
        ConnectionAdapterExtension.inject(connection_class)
        TransactionExtension.inject(ActiveRecord::ConnectionAdapters::RealTransaction)
      end

      @lock.synchronize do
        @cache_subscription ||= ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start_time, _end_time, _id, payload|
          if payload[:cached] && !IGNORED_STATEMENTS.include?(payload[:name])
            counter = current_counter
            counter.cached_query_count += 1 if counter.is_a?(Counter)
          end
        end
      end
    end

    private

    # The counter is stored in ActiveSupport::IsolatedExecutionState so that it follows the
    # application's configured isolation level (thread or fiber).
    def current_counter
      ActiveSupport::IsolatedExecutionState[:active_record_query_counter]
    end

    def current_counter=(counter)
      ActiveSupport::IsolatedExecutionState[:active_record_query_counter] = counter
    end

    # The connection timer accumulates the connection setup time for the query currently being
    # measured. It is stored with the same isolation as the counter (see {#current_counter}).
    def connection_timer
      ActiveSupport::IsolatedExecutionState[:active_record_query_counter_connection_timer]
    end

    def connection_timer=(timer)
      ActiveSupport::IsolatedExecutionState[:active_record_query_counter_connection_timer] = timer
    end

    def send_notification(name, start_time, end_time, payload = {})
      id = "#{name}-#{SecureRandom.hex}"
      ActiveSupport::Notifications.publish("active_record_query_counter.#{name}", start_time, end_time, id, payload)
    end

    def notification_payload(sql:, binds:, row_count:, trace:, elapsed_time:, gc_time:, cpu_time:, connection_time:)
      {
        sql: sql,
        binds: binds,
        row_count: row_count,
        trace: trace,
        elapsed_time: (elapsed_time * 1000.0).round(6),
        gc_time: (gc_time * 1000.0).round(6),
        cpu_time: (cpu_time * 1000.0).round(6),
        connection_time: (connection_time * 1000.0).round(6)
      }
    end

    # Estimate the time spent waiting on the database by subtracting the connection setup time,
    # GC time, and thread CPU time from the wall clock time the query took.
    #
    # The connection setup time is a measured sub-interval of the wall clock time that was spent
    # establishing, verifying, or reconnecting the database connection rather than executing the
    # query, so it is removed first. This is the time that inflates a trivial query into a
    # multi-second one after an idle period or a database failover.
    #
    # The GC time and CPU time normally measure distinct, non-overlapping intervals: a GC pause
    # triggered by another thread happens while this thread is parked waiting on the database
    # (off CPU, so it does not count as CPU time), while CPU time covers the Ruby work of
    # building the result. They only overlap when the query's own thread triggers a GC, which
    # runs on that thread and so counts as both GC time and CPU time. When that overlap is large
    # enough to drive the result negative, only the larger of the two is subtracted so the shared
    # interval is removed once. The result is clamped so it never exceeds the wall clock time and
    # is never negative.
    #
    # @param elapsed_time [Float] the wall clock time the query took in seconds
    # @param gc_time [Float] the GC time in seconds that elapsed while the query ran
    # @param cpu_time [Float] the thread CPU time in seconds spent while the query ran
    # @param connection_time [Float] the time in seconds spent establishing, verifying, or
    #   reconnecting the database connection while the query ran
    # @return [Float] the estimated database time in seconds
    def database_query_time(elapsed_time, gc_time, cpu_time, connection_time = 0.0)
      return 0.0 if elapsed_time <= 0.0

      wait_time = (elapsed_time - connection_time).clamp(0.0, elapsed_time)
      return 0.0 if wait_time <= 0.0

      query_time = wait_time - (gc_time + cpu_time)
      query_time = wait_time - [gc_time, cpu_time].max if query_time.negative?
      query_time.clamp(0.0, wait_time)
    end

    def backtrace
      caller.reject { |line| line.start_with?(__dir__) }
    end
  end
end
