# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Module to prepend to the connection adapter to inject the counting behavior.
  module ConnectionAdapterExtension
    def exec_query(*args, **kwargs)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = super
      if result.is_a?(ActiveRecord::Result)
        elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        ActiveRecordQueryCounter.increment(result.length, elapsed_time)
      end
      result
    end
  end
end
