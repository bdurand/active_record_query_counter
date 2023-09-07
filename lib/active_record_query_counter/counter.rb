# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Data structure for storing query information encountered within a block.
  class Counter
    attr_accessor :query_count, :row_count, :query_time
    attr_reader :transactions

    def initialize
      @query_count = 0
      @row_count = 0
      @query_time = 0.0
      @transactions = {}
    end

    # Return the number of transactions that have been tracked by the counter.
    #
    # @return [Integer]
    def transaction_count
      @transactions.size
    end

    # Return the total time spent in transactions that have been tracked by the counter.
    #
    # @return [Float]
    def transaction_time
      @transactions.values.sum(&:elapsed_time)
    end

    # Return that would have been spent inside a transaction if all transactions tracked
    # by the counter were nested inside a single transaction. For example, if the counter
    # tracked two transactions, one that took 1 second, one that took 2 seconds, and with
    # 3 seconds between them, this method would return 6 seconds. This information is useful
    # for determining the impact of wrapping code in a single transaction. It is usually best
    # to wrap multiple updates in a single transaction to maintain data integrity. However,
    # if the updates are spread out over a longer period of time, it may be better to leave
    # them outside of a transaction so that you don't hold locks on rows for too long.
    #
    # @return [Float]
    def single_transaction_time
      return 0.0 if @transactions.empty?

      start_time = @transactions.values.collect(&:start_time).min
      end_time = @transactions.values.collect(&:end_time).max
      end_time - start_time
    end
  end
end
