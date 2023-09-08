# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Extension to ActiveRecord::ConnectionAdapters::TransactionManager to count transactions.
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
end
