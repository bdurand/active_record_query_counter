# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Data structure for storing information about a transaction. Note that the start and end
  # times are monotonic time and not wall clock time.
  class TransactionInfo
    attr_accessor :count, :start_time, :end_time, :elapsed_time, :trace

    def initialize
      @count = 0
      @elapsed_time = 0.0
      @start_time = nil
      @end_time = nil
      @trace = nil
    end
  end
end
