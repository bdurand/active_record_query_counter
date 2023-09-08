# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Module to prepend to the connection adapter to inject the counting behavior.
  module ConnectionAdapterExtension
    def exec_query(sql, name = nil, binds = [], *args, **kwargs)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = super
      if result.is_a?(ActiveRecord::Result)
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ActiveRecordQueryCounter.add_query(sql, name, binds, result.length, start_time, end_time)
      end
      result
    end
  end
end
