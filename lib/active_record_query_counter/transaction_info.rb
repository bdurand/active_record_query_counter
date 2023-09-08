# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Data structure for storing information about a transaction. Note that the start and end
  # times are monotonic time and not wall clock time.
  class TransactionInfo
    attr_reader :start_time, :end_time, :trace

    def initialize(start_time:, end_time:, trace:)
      @start_time = start_time
      @end_time = end_time
      @trace = trace
    end

    # Return the time spent in the transaction.
    #
    # @return [Float]
    def elapsed_time
      end_time - start_time
    end
  end
end
