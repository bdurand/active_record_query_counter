# frozen_string_literal: true

require_relative "active_record_query_counter/counter"
require_relative "active_record_query_counter/transaction_info"
require_relative "active_record_query_counter/connection_adapter_extension"
require_relative "active_record_query_counter/transaction_manager_extension"
require_relative "active_record_query_counter/rack_middleware"
require_relative "active_record_query_counter/sidekiq_middleware"
require_relative "active_record_query_counter/version"

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
  IGNORED_STATEMENTS = %w[CACHE SCHEMA EXPLAIN].freeze
  private_constant :IGNORED_STATEMENTS

  class << self
    attr_accessor :query_time_threshold
    attr_accessor :row_count_threshold
    attr_accessor :transaction_time_threshold
    attr_accessor :transaction_count_threshold

    # Enable query counting within a block.
    #
    # @return [Object] the result of the block
    def count_queries
      current = Thread.current[:database_query_counter]
      begin
        counter = Counter.new
        Thread.current[:database_query_counter] = counter
        retval = yield

        if transaction_count_threshold && counter.transaction_count >= transaction_count_threshold
          send_notification(
            "active_record_query_counter.transaction_count",
            counter.first_transaction_start_time,
            counter.last_transaction_end_time,
            transaction_count: counter.transaction_count
          )
        end

        retval
      ensure
        Thread.current[:database_query_counter] = current
      end
    end

    # Increment the query counters.
    #
    # @param row_count [Integer] the number of rows returned by the query
    # @param elapsed_time [Float] the time spent executing the query
    # @return [void]
    # @api private
    def add_query(sql, name, binds, row_count, start_time, end_time)
      return if IGNORED_STATEMENTS.include?(name)

      counter = Thread.current[:database_query_counter]
      return unless counter

      elapsed_time = end_time - start_time
      counter.query_count += 1
      counter.row_count += row_count
      counter.query_time += elapsed_time

      if query_time_threshold && elapsed_time >= query_time_threshold
        send_notification("active_record_query_counter.query_time", start_time, end_time, sql: sql, binds: binds)
      end

      if row_count_threshold && row_count >= row_count_threshold
        send_notification("active_record_query_counter.row_count", start_time, end_time, sql: sql, binds: binds, row_count: row_count)
      end
    end

    # Increment the transaction counters.
    #
    # @param start_time [Float] the time the transaction started
    # @param end_time [Float] the time the transaction ended
    # @return [void]
    # @api private
    def add_transaction(start_time, end_time)
      counter = Thread.current[:database_query_counter]
      if counter.is_a?(Counter)
        trace = caller
        index = 0
        caller.each do |line|
          break unless line.start_with?(__dir__)
          index += 1
        end
        trace = trace[index, trace.length]
        counter.add_transaction(trace: trace, start_time: start_time, end_time: end_time)
      end

      if transaction_time_threshold && end_time - start_time >= transaction_time_threshold
        send_notification("active_record_query_counter.transaction_time", start_time, end_time)
      end
    end

    # Return the number of queries that have been counted within the current block.
    # Returns nil if not inside a block where queries are being counted.
    #
    # @return [Integer, nil]
    def query_count
      counter = Thread.current[:database_query_counter]
      counter.query_count if counter.is_a?(Counter)
    end

    # Return the number of rows that have been counted within the current block.
    # Returns nil if not inside a block where queries are being counted.
    #
    # @return [Integer, nil]
    def row_count
      counter = Thread.current[:database_query_counter]
      counter.row_count if counter.is_a?(Counter)
    end

    # Return the total time spent executing queries within the current block.
    # Returns nil if not inside a block where queries are being counted.
    #
    # @return [Float, nil]
    def query_time
      counter = Thread.current[:database_query_counter]
      counter.query_time if counter.is_a?(Counter)
    end

    # Return the number of transactions that have been counted within the current block.
    # Returns nil if not inside a block where queries are being counted.
    #
    # @return [Integer, nil]
    def transaction_count
      counter = Thread.current[:database_query_counter]
      counter.transaction_count if counter.is_a?(Counter)
    end

    # Return the total time spent in transactions that have been counted within the current block.
    # Returns nil if not inside a block where queries are being counted.
    #
    # @return [Float, nil]
    def transaction_time
      counter = Thread.current[:database_query_counter]
      counter.transaction_time if counter.is_a?(Counter)
    end

    # Return the time when the first transaction began within the current block.
    # Returns nil if not inside a block where queries are being counted or there are no transactions.
    #
    # @return [Float, nil] the monotonic time when the first transaction began,
    def first_transaction_start_time
      counter = Thread.current[:database_query_counter]
      counter.first_transaction_start_time if counter.is_a?(Counter)
    end

    # Return the time when the last transaction ended within the current block.
    # Returns nil if not inside a block where queries are being counted or there are no transactions.
    #
    # @return [Float, nil] the monotonic time when the last transaction ended,
    def last_transaction_end_time
      counter = Thread.current[:database_query_counter]
      counter.transactions.last&.end_time if counter.is_a?(Counter)
    end

    # Return the total time that would have been spent in transactions if all transactions
    # tracked by the counter were nested inside a single transaction. This is useful for
    # determining the effects of wrapping code in a single transaction. For example, if
    # if there were two transactions that each took 1 second and they were called 2 seconds
    # apart, then the single transaction time would be 4 seconds since this is how long it would
    # have taken if they were nested inside a single transaction.
    #
    # @return [Float]
    def single_transaction_time
      start_time = first_transaction_start_time
      end_time = transactions.last&.end_time
      (start_time && end_time) ? end_time - start_time : 0.0
    end

    # Return an array of transaction information for any transactions that have been counted
    # within the current block. Returns nil if not inside a block where queries are being counted.
    #
    # @return [Array<ActiveRecordQueryCounter::TransactionInfo>, nil]
    def transactions
      counter = Thread.current[:database_query_counter]
      counter.transactions if counter.is_a?(Counter)
    end

    # Return the query info as a hash with keys :query_count, :row_count, :query_time
    # :transaction_count, and :transaction_type or nil if not inside a block where queries
    # are being counted.
    #
    # @return [Hash, nil]
    def info
      counter = Thread.current[:database_query_counter]
      if counter.is_a?(Counter)
        {
          query_count: counter.query_count,
          row_count: counter.row_count,
          query_time: counter.query_time,
          transaction_count: counter.transaction_count,
          transaction_time: counter.transaction_time
        }
      end
    end

    # Enable the query counting behavior on a connection adapter class.
    #
    # @param connection_class [Class] the connection adapter class to extend
    # @return [void]
    def enable!(connection_class)
      unless connection_class.include?(ConnectionAdapterExtension)
        connection_class.prepend(ConnectionAdapterExtension)
      end
      unless ActiveRecord::ConnectionAdapters::TransactionManager.include?(TransactionManagerExtension)
        ActiveRecord::ConnectionAdapters::TransactionManager.prepend(TransactionManagerExtension)
      end
    end

    private

    def send_notification(name, start_time, end_time, payload = {})
      id = "#{name}-#{SecureRandom.hex}"
      trace = caller.reject { |line| line.start_with?(__dir__) }
      ActiveSupport::Notifications.publish(name, start_time, end_time, id, payload.merge(trace: trace))
    end
  end
end
