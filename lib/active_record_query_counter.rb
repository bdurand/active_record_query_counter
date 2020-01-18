# frozen_string_literal: true

# Everything you need to count ActiveRecord queries and row counts within a block.
#
# Usage:
#
#  ActiveRecordQueryCounter.count_queries do
#    yield
#    puts ActiveRecordQueryCounter.query_count
#    puts ActiveRecordQueryCounter.row_count
#  end
module ActiveRecordQueryCounter

  class << self

    # Enable query counting within a block.
    def count_queries
      current = Thread.current[:database_query_counter]
      begin
        Thread.current[:database_query_counter] = [0, 0, 0.0]
        yield
      ensure
        Thread.current[:database_query_counter] = current
      end
    end

    # Increment the query counters
    def increment(row_count, elapsed_time)
      current = Thread.current[:database_query_counter]
      if current.is_a?(Array)
        current[0] = current[0].to_i + 1
        current[1] = current[1].to_i + row_count
        current[2] = current[2].to_f + elapsed_time
      end
    end

    def query_count
      current = Thread.current[:database_query_counter]
      current[0].to_i if current.is_a?(Array)
    end

    def row_count
      current = Thread.current[:database_query_counter]
      current[1].to_i if current.is_a?(Array)
    end

    def query_time
      current = Thread.current[:database_query_counter]
      current[2].to_f if current.is_a?(Array)
    end

    # Return the query info as a hash with keys :query_count, :row_count, :query_time.
    # or nil if not inside a block where queries are being counted.
    def info
      current = Thread.current[:database_query_counter]
      if current
        {
          :query_count => current[0],
          :row_count => current[1],
          :query_time => current[2]
        }
      else
        nil
      end
    end

    # Enable the query counting behavior on a connection adapter class.
    def enable!(connection_class)
      unless connection_class.include?(ConnectionAdapterExtension)
        connection_class.prepend(ConnectionAdapterExtension)
      end
    end

  end

  # Module to prepend to the connection adapter to inject the counting behavior.
  module ConnectionAdapterExtension

    def exec_query(*args)
      start_time = Time.now
      result = super
      if result.is_a?(ActiveRecord::Result)
        ActiveRecordQueryCounter.increment(result.length, Time.now - start_time)
      end
      result
    end

  end

  # Rack middleware to count queries on a request.
  class RackMiddleware

    def initialize(app)
      @app = app
    end

    def call(env)
      ActiveRecordQueryCounter.count_queries { @app.call(env) }
    end

  end

  # Sidekiq middleware to count queries on a job.
  class SidekiqMiddleware

    def call(worker, job, queue, &block)
      ActiveRecordQueryCounter.count_queries(&block)
    end

  end

end
