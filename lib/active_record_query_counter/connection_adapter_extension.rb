# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Module to prepend to the connection adapter to inject the counting behavior.
  module ConnectionAdapterExtension
    # Clock used to measure the CPU time consumed by the current thread while a query runs.
    # It is not available on every platform (e.g. Windows), in which case CPU time is not
    # measured and is treated as zero.
    CPU_CLOCK_ID = (Process::CLOCK_THREAD_CPUTIME_ID if defined?(Process::CLOCK_THREAD_CPUTIME_ID))

    class << self
      def inject(connection_class)
        # Rails 7.1+ uses internal_exec_query instead of exec_query.
        mod = (connection_class.method_defined?(:internal_exec_query) ? InternalExecQuery : ExecQuery)
        unless connection_class.include?(mod)
          connection_class.prepend(mod)
        end
      end

      # Measure a query by wrapping its execution. In addition to the wall clock time, the GC
      # time and thread CPU time spent while the query runs are captured so that the time
      # actually spent waiting on the database can be isolated from time lost to garbage
      # collection and Ruby VM work.
      #
      # @param sql [String] the SQL statement being executed
      # @param name [String, nil] the name of the query
      # @param binds [Array] the bind parameters
      # @yield executes the query and returns its result
      # @return [Object] the result of the query
      def measure_query(sql, name, binds)
        gc_start = GC.total_time
        cpu_start = current_cpu_time
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        if result.is_a?(ActiveRecord::Result)
          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          cpu_time = current_cpu_time - cpu_start
          gc_time = (GC.total_time - gc_start) / 1_000_000_000.0
          ActiveRecordQueryCounter.add_query(sql, name, binds, result.length, start_time, end_time, gc_time, cpu_time)
        end
        result
      end

      private

      # The current thread CPU time in seconds, or 0.0 when the platform does not support it.
      #
      # @return [Float]
      def current_cpu_time
        CPU_CLOCK_ID ? Process.clock_gettime(CPU_CLOCK_ID) : 0.0
      end
    end

    module ExecQuery
      def exec_query(sql, name = nil, binds = [], ...)
        ConnectionAdapterExtension.measure_query(sql, name, binds) { super }
      end
    end

    module InternalExecQuery
      def internal_exec_query(sql, name = nil, binds = [], ...)
        ConnectionAdapterExtension.measure_query(sql, name, binds) { super }
      end
    end
  end
end
