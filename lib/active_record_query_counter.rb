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
  class Counter
    attr_accessor :query_count, :row_count, :query_time
    attr_reader :transactions

    def initialize
      @query_count = 0
      @row_count = 0
      @query_time = 0.0
      @transactions = {}
    end

    def transaction_count
      @transactions.size
    end

    def transaction_time
      @transactions.values.sum { |count, time| time }
    end
  end

  class << self
    # Enable query counting within a block.
    def count_queries
      current = Thread.current[:database_query_counter]
      begin
        Thread.current[:database_query_counter] = Counter.new
        yield
      ensure
        Thread.current[:database_query_counter] = current
      end
    end

    # Increment the query counters
    def increment(row_count, elapsed_time)
      counter = Thread.current[:database_query_counter]
      if counter.is_a?(Counter)
        counter.query_count += 1
        counter.row_count += row_count
        counter.query_time += elapsed_time
      end
    end

    def increment_transaction(elapsed_time)
      counter = Thread.current[:database_query_counter]
      if counter.is_a?(Counter)
        trace = caller
        index = 0
        caller.each do |line|
          break unless line.start_with?(__FILE__)
          index += 1
        end
        trace = trace[index, trace.length]
        info = counter.transactions[trace]
        if info
          info[0] += 1
          info[1] += elapsed_time
        else
          info = [1, elapsed_time]
          counter.transactions[trace] = info
        end
      end
    end

    def query_count
      counter = Thread.current[:database_query_counter]
      counter.query_count if counter.is_a?(Counter)
    end

    def row_count
      counter = Thread.current[:database_query_counter]
      counter.row_count if counter.is_a?(Counter)
    end

    def query_time
      counter = Thread.current[:database_query_counter]
      counter.query_time if counter.is_a?(Counter)
    end

    def transaction_count
      counter = Thread.current[:database_query_counter]
      counter.transaction_count if counter.is_a?(Counter)
    end

    def transaction_time
      counter = Thread.current[:database_query_counter]
      counter.transaction_time if counter.is_a?(Counter)
    end

    def transactions
      counter = Thread.current[:database_query_counter]
      counter.transactions.dup if counter.is_a?(Counter)
    end

    # Return the query info as a hash with keys :query_count, :row_count, :query_time
    # :transaction_count, and :transaction_type or nil if not inside a block where queries
    # are being counted.
    def info
      counter = Thread.current[:database_query_counter]
      if counter.is_a?(Counter)
        {
          query_count: counter.query_count,
          row_count: counter.row_count,
          query_time: counter.query_time,
          transaction_count: counter.transaction_count,
          transaction_time: counter.transaction_time
        }
      end
    end

    # Enable the query counting behavior on a connection adapter class.
    def enable!(connection_class)
      unless connection_class.include?(ConnectionAdapterExtension)
        connection_class.prepend(ConnectionAdapterExtension)
      end
      unless ActiveRecord::ConnectionAdapters::TransactionManager.include?(TransactionManagerExtension)
        ActiveRecord::ConnectionAdapters::TransactionManager.prepend(TransactionManagerExtension)
      end
    end
  end

  # Module to prepend to the connection adapter to inject the counting behavior.
  module ConnectionAdapterExtension
    def exec_query(*args, **kwargs)
      start_time = Time.now
      result = super
      if result.is_a?(ActiveRecord::Result)
        ActiveRecordQueryCounter.increment(result.length, Time.now - start_time)
      end
      result
    end
  end

  module TransactionManagerExtension
    def begin_transaction(*args)
      if open_transactions == 0
        @active_record_query_counter_transaction_start_time = Time.current
      end
      super
    end

    def commit_transaction(*args)
      if @active_record_query_counter_transaction_start_time && open_transactions == 1
        ActiveRecordQueryCounter.increment_transaction(Time.current - @active_record_query_counter_transaction_start_time)
        @active_record_query_counter_transaction_start_time = nil
      end
      super
    end

    def rollback_transaction(*args)
      if @active_record_query_counter_transaction_start_time && open_transactions == 1
        ActiveRecordQueryCounter.increment_transaction(Time.current - @active_record_query_counter_transaction_start_time)
        @active_record_query_counter_transaction_start_time = nil
      end
      super
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
