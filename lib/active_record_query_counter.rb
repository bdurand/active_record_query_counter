# frozen_string_literal: true

require_relative "active_record_query_counter/connection_adapter_extension"
require_relative "active_record_query_counter/counter"
require_relative "active_record_query_counter/rack_middleware"
require_relative "active_record_query_counter/sidekiq_middleware"
require_relative "active_record_query_counter/thresholds"
require_relative "active_record_query_counter/transaction_info"
require_relative "active_record_query_counter/transaction_manager_extension"
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
          transaction_threshold = (counter.thresholds.transaction_count || -1)
          if transaction_threshold >= 0 && transaction_count >= transaction_threshold
            send_notification("transaction_count", counter.first_transaction_start_time, counter.last_transaction_end_time, transactions: counter.transactions)
          end
        end

        retval
      ensure
        self.current_counter = save_counter
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

      counter = current_counter
      return unless counter.is_a?(Counter)

      elapsed_time = end_time - start_time
      counter.query_count += 1
      counter.row_count += row_count
      counter.query_time += elapsed_time

      query_time_threshold = (counter.thresholds.query_time || -1)
      if query_time_threshold >= 0 && elapsed_time >= query_time_threshold
        send_notification("query_time", start_time, end_time, sql: sql, binds: binds, trace: backtrace)
      end

      row_count_threshold = (counter.thresholds.row_count || -1)
      if row_count_threshold >= 0 && row_count >= row_count_threshold
        send_notification("row_count", start_time, end_time, sql: sql, binds: binds, row_count: row_count, trace: backtrace)
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

      transaction_time_threshold = (counter.thresholds.transaction_time || -1)
      if transaction_time_threshold >= 0 && end_time - start_time >= transaction_time_threshold
        send_notification("transaction_time", start_time, end_time, trace: backtrace)
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
      counter.transactions.last&.end_time if counter.is_a?(Counter)
    end

    # Return an array of transaction information for any transactions that have been counted
    # within the current block. Returns nil if not inside a block where queries are being counted.
    #
    # @return [Array<ActiveRecordQueryCounter::TransactionInfo>, nil]
    def transactions
      counter = current_counter
      counter.transactions if counter.is_a?(Counter)
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
          transaction_count: counter.transaction_count,
          transaction_time: counter.transaction_time
        }
      end
    end

    # The global notification thresholds for sending notifications. The values set in these
    # thresholds are used as the default values.
    #
    # @return [ActiveRecordQueryCounter::Thresholds]
    def default_thresholds
      @default_thresholds ||= Thresholds.new
    end

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
      unless connection_class.include?(ConnectionAdapterExtension)
        connection_class.prepend(ConnectionAdapterExtension)
      end
      unless ActiveRecord::ConnectionAdapters::TransactionManager.include?(TransactionManagerExtension)
        ActiveRecord::ConnectionAdapters::TransactionManager.prepend(TransactionManagerExtension)
      end
    end

    private

    def current_counter
      Thread.current[:active_record_query_counter]
    end

    def current_counter=(counter)
      Thread.current[:active_record_query_counter] = counter
    end

    def send_notification(name, start_time, end_time, payload = {})
      id = "#{name}-#{SecureRandom.hex}"
      ActiveSupport::Notifications.publish("active_record_query_counter.#{name}", start_time, end_time, id, payload)
    end

    def backtrace
      caller.reject { |line| line.start_with?(__dir__) }
    end
  end
end
