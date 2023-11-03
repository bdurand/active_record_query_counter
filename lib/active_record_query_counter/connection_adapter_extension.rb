# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Module to prepend to the connection adapter to inject the counting behavior.
  module ConnectionAdapterExtension
    class << self
      def inject(connection_class)
        # Rails 7.1+ uses internal_exec_query instead of exec_query.
        mod = (connection_class.instance_methods.include?(:internal_exec_query) ? InternalExecQuery : ExecQuery)
        unless connection_class.include?(mod)
          connection_class.prepend(mod)
        end
      end
    end

    module ExecQuery
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

    module InternalExecQuery
      def internal_exec_query(sql, name = nil, binds = [], *args, **kwargs)
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
end
