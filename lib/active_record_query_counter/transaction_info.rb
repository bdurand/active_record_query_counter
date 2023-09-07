# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Data structure for storing information about a transaction. Note that the start and end
  # times are monotonic time and not wall clock time.
  class TransactionInfo
    attr_accessor :count, :start_time, :end_time

    def initialize
      @count = 0
      @start_time = nil
      @end_time = nil
    end

    # Return the total time spent in this transaction.
    #
    # @return [Float]
    def elapsed_time
      @end_time - @start_time
    end
  end
end
