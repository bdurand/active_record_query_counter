# frozen_string_literal: true

# Everything you need to count ActiveRecord queries and row counts within a block.
#
# @example
#
#  ActiveRecordQueryCounter.count_queries do
#    yield
#    puts ActiveRecordQueryCounter.query_count
#    puts ActiveRecordQueryCounter.row_count
#  end
module ActiveRecordQueryCounter
  # Data structure for storing query information encountered within a block.
  class Counter
    attr_accessor :query_count, :row_count, :query_time
    attr_reader :transactions

    def initialize
      @query_count = 0
      @row_count = 0
      @query_time = 0.0
      @transactions = {}
    end

    # Return the number of transactions that have been tracked by the counter.
    #
    # @return [Integer]
    def transaction_count
      @transactions.size
    end

    # Return the total time spent in transactions that have been tracked by the counter.
    #
    # @return [Float]
    def transaction_time
      @transactions.values.sum(&:elapsed_time)
    end

    # Return that would have been spent inside a transaction if all transactions tracked
    # by the counter were nested inside a single transaction. For example, if the counter
    # tracked two transactions, one that took 1 second, one that took 2 seconds, and with
    # 3 seconds between them, this method would return 6 seconds. This information is useful
    # for determining the impact of wrapping code in a single transaction. It is usually best
    # to wrap multiple updates in a single transaction to maintain data integrity. However,
    # if the updates are spread out over a longer period of time, it may be better to leave
    # them outside of a transaction so that you don't hold locks on rows for too long.
    #
    # @return [Float]
    def single_transaction_time
      return 0.0 if @transactions.empty?

      @transactions.last.end_time - @transactions.first.start_time
    end
  end

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

  class << self
    # Enable query counting within a block.
    #
    # @return [Object] the result of the block
    def count_queries
      current = Thread.current[:database_query_counter]
      begin
        Thread.current[:database_query_counter] = Counter.new
        yield
      ensure
        Thread.current[:database_query_counter] = current
      end
    end

    # Increment the query counters.
    #
    # @param row_count [Integer] the number of rows returned by the query
    # @param elapsed_time [Float] the time spent executing the query
    # @return [void]
    def increment(row_count, elapsed_time)
      counter = Thread.current[:database_query_counter]
      if counter.is_a?(Counter)
        counter.query_count += 1
        counter.row_count += row_count
        counter.query_time += elapsed_time
      end
    end

    # Increment the transaction counters.
    #
    # @param start_time [Float] the time the transaction started
    # @param end_time [Float] the time the transaction ended
    # @return [void]
    def increment_transaction(start_time, end_time)
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
          info.count += 1
          info.end_time = end_time
        else
          info = TransactionInfo.new
          info.count = 1
          info.start_time = start_time
          info.end_time = end_time
          counter.transactions[trace] = info
        end
      end
    end

    # Return the number of queries that have been counted within the current block.
    # Returns nil if not inside a block where queries are being counted.
    #
    # @return [Integer, nil]
    def query_count
      counter = Thread.current[:database_query_counter]
      counter.query_count if counter.is_a?(Counter)
    end

    # Return the number of rows that have been counted within the current block.
    # Returns nil if not inside a block where queries are being counted.
    #
    # @return [Integer, nil]
    def row_count
      counter = Thread.current[:database_query_counter]
      counter.row_count if counter.is_a?(Counter)
    end

    # Return the total time spent executing queries within the current block.
    # Returns nil if not inside a block where queries are being counted.
    #
    # @return [Float, nil]
    def query_time
      counter = Thread.current[:database_query_counter]
      counter.query_time if counter.is_a?(Counter)
    end

    # Return the number of transactions that have been counted within the current block.
    # Returns nil if not inside a block where queries are being counted.
    #
    # @return [Integer, nil]
    def transaction_count
      counter = Thread.current[:database_query_counter]
      counter.transaction_count if counter.is_a?(Counter)
    end

    # Return the total time spent in transactions that have been counted within the current block.
    # Returns nil if not inside a block where queries are being counted.
    #
    # @return [Float, nil]
    def transaction_time
      counter = Thread.current[:database_query_counter]
      counter.transaction_time if counter.is_a?(Counter)
    end

    # Return the total time that would have been spent in transactions if all transactions
    # tracked by the counter were nested inside a single transaction. See {Counter#single_transaction_time}
    # for more information. Returns nil if not inside a block where queries are being counted.
    #
    # @return [Float, nil]
    def single_transaction_time
      counter = Thread.current[:database_query_counter]
      counter.single_transaction_time if counter.is_a?(Counter)
    end

    # Return an array of transaction information for any transactions that have been counted
    # within the current block. Returns nil if not inside a block where queries are being counted.
    #
    # @return [Array<ActiveRecordQueryCounter::TransactionInfo>, nil]
    def transactions
      counter = Thread.current[:database_query_counter]
      counter.transactions.dup if counter.is_a?(Counter)
    end

    # Return the query info as a hash with keys :query_count, :row_count, :query_time
    # :transaction_count, and :transaction_type or nil if not inside a block where queries
    # are being counted.
    #
    # @return [Hash, nil]
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
    #
    # @param connection_class [Class] the connection adapter class to extend
    # @return [void]
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
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = super
      if result.is_a?(ActiveRecord::Result)
        elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        ActiveRecordQueryCounter.increment(result.length, elapsed_time)
      end
      result
    end
  end

  module TransactionManagerExtension
    def begin_transaction(*args, **kwargs)
      if open_transactions == 0
        @active_record_query_counter_transaction_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
      super
    end

    def commit_transaction(*args)
      if @active_record_query_counter_transaction_start_time && open_transactions == 1
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ActiveRecordQueryCounter.increment_transaction(@active_record_query_counter_transaction_start_time, end_time)
        @active_record_query_counter_transaction_start_time = nil
      end
      super
    end

    def rollback_transaction(*args)
      if @active_record_query_counter_transaction_start_time && open_transactions == 1
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ActiveRecordQueryCounter.increment_transaction(@active_record_query_counter_transaction_start_time, end_time)
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
