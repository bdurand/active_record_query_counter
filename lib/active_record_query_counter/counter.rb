# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Data structure for storing query information encountered within a block.
  class Counter
    attr_accessor :query_count, :row_count, :query_time, :cached_query_count, :rollback_count
    attr_reader :thresholds

    def initialize
      @query_count = 0
      @row_count = 0
      @query_time = 0.0
      @cached_query_count = 0
      @transactions_hash = {}
      @thresholds = ActiveRecordQueryCounter.default_thresholds.dup
      @rollback_count = 0
    end

    # Return the percentage of queries that used the query cache instead of going to the database.
    #
    # @return [Float]
    def cache_hit_rate
      total_queries = query_count + cached_query_count
      if total_queries > 0
        (cached_query_count.to_f / total_queries)
      else
        0.0
      end
    end

    # Return an array of transaction information for any transactions that have been tracked
    # by the counter.
    #
    # @return [Array<ActiveRecordQueryCounter::TransactionInfo>]
    def transactions
      @transactions_hash.values.flatten.sort_by(&:start_time)
    end

    # Add a tracked transaction.
    #
    # @param trace [Array<String>] the trace of the transaction
    # @param start_time [Float] the monotonic time when the transaction began
    # @param end_time [Float] the monotonic time when the transaction ended
    # @return [void]
    # @api private
    def add_transaction(trace:, start_time:, end_time:)
      trace_transactions = @transactions_hash[trace]
      if trace_transactions
        # Memory optimization so that we don't store duplicate traces for every transaction in a loop.
        trace = trace_transactions.first.trace
      else
        trace_transactions = []
        @transactions_hash[trace] = trace_transactions
      end

      trace_transactions << TransactionInfo.new(start_time: start_time, end_time: end_time, trace: trace)
    end

    # Return the number of transactions that have been tracked by the counter.
    #
    # @return [Integer]
    def transaction_count
      @transactions_hash.values.flatten.size
    end

    # Return the total time spent in transactions that have been tracked by the counter.
    #
    # @return [Float]
    def transaction_time
      @transactions_hash.values.flatten.sum(&:elapsed_time)
    end

    # Get the time when the first transaction began.
    #
    # @return [Float, nil] the monotonic time when the first transaction began,
    #   or nil if no transactions have been tracked
    def first_transaction_start_time
      transactions.first&.start_time
    end

    # Get the time when the last transaction completed.
    #
    # @return [Float, nil] the monotonic time when the first transaction completed,
    #   or nil if no transactions have been tracked
    def last_transaction_end_time
      transactions.max_by(&:end_time)&.end_time
    end
  end
end
