# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Module to prepend to the connection adapter to inject the counting behavior.
  module ConnectionAdapterExtension
    # Clock used to measure the CPU time consumed by the current thread while a query runs.
    # It is not available on every platform (e.g. Windows), in which case CPU time is not
    # measured and is treated as zero.
    CPU_CLOCK_ID = (Process::CLOCK_THREAD_CPUTIME_ID if defined?(Process::CLOCK_THREAD_CPUTIME_ID))

    # Connection adapter methods that establish, verify, or reconnect the underlying database
    # connection. When these run inside a query (for example when a stale connection is
    # re-established after an idle period or a database failover), the wall clock time they
    # consume is spent setting up the connection rather than executing the query. It is measured
    # separately so it can be subtracted from the reported query time. `connect!` was only added
    # in Rails 7.1, so it is not present on every supported version.
    CONNECTION_SETUP_METHODS = %i[connect! reconnect! verify!].freeze

    class << self
      def inject(connection_class)
        # Rails 7.1+ uses internal_exec_query instead of exec_query.
        mod = (connection_class.method_defined?(:internal_exec_query) ? InternalExecQuery : ExecQuery)
        unless connection_class.include?(mod)
          connection_class.prepend(mod)
        end

        unless connection_class.include?(ConnectionSetupExtension)
          connection_class.prepend(ConnectionSetupExtension)
        end
      end

      # Measure a query by wrapping its execution. In addition to the wall clock time, the GC
      # time, thread CPU time, and connection setup time spent while the query runs are captured
      # so that the time actually spent waiting on the database can be isolated from time lost to
      # garbage collection, Ruby VM work, and (re)establishing the database connection.
      #
      # @param sql [String] the SQL statement being executed
      # @param name [String, nil] the name of the query
      # @param binds [Array] the bind parameters
      # @yield executes the query and returns its result
      # @return [Object] the result of the query
      def measure_query(sql, name, binds)
        gc_start = GC.total_time
        cpu_start = current_cpu_time
        previous_timer = ActiveRecordQueryCounter.start_connection_timer
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          result = yield
        ensure
          connection_time = ActiveRecordQueryCounter.stop_connection_timer(previous_timer)
        end
        if result.is_a?(ActiveRecord::Result)
          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          cpu_time = current_cpu_time - cpu_start
          gc_time = (GC.total_time - gc_start) / 1_000_000_000.0
          ActiveRecordQueryCounter.add_query(sql, name, binds, result.length, start_time, end_time, gc_time, cpu_time, connection_time)
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
      def exec_query(sql, name = nil, binds = [], **kwargs)
        ConnectionAdapterExtension.measure_query(sql, name, binds) { super }
      end
    end

    module InternalExecQuery
      def internal_exec_query(sql, name = nil, binds = [], **kwargs)
        ConnectionAdapterExtension.measure_query(sql, name, binds) { super }
      end
    end

    # Module prepended to the connection adapter to measure the wall clock time spent
    # establishing, verifying, or reconnecting the database connection while a query is running
    # (see {CONNECTION_SETUP_METHODS}). The measured time is accumulated on the current query's
    # connection timer so it can be subtracted from the reported query time.
    module ConnectionSetupExtension
      def connect!(*args, **kwargs, &block)
        # `defined?(super)` guards against versions where the method does not exist so this
        # prepended definition becomes a harmless no-op instead of raising a NoMethodError.
        return unless defined?(super)

        ActiveRecordQueryCounter.measure_connection_setup { super }
      end

      def reconnect!(*args, **kwargs, &block)
        return unless defined?(super)

        ActiveRecordQueryCounter.measure_connection_setup { super }
      end

      def verify!(*args, **kwargs, &block)
        return unless defined?(super)

        ActiveRecordQueryCounter.measure_connection_setup { super }
      end
    end
  end
end
