# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Extension to ActiveRecord::ConnectionAdapters::TransactionManager to count transactions.
  module TransactionManagerExtension
    class << self
      def inject(transaction_manager_class)
        unless transaction_manager_class.include?(self)
          transaction_manager_class.prepend(self)
        end
      end
    end

    def begin_transaction(*args, **kwargs)
      if open_transactions == 0
        @active_record_query_counter_transaction_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
      super
    end

    def commit_transaction(*args)
      if @active_record_query_counter_transaction_start_time && open_transactions == 1
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ActiveRecordQueryCounter.add_transaction(@active_record_query_counter_transaction_start_time, end_time)
        @active_record_query_counter_transaction_start_time = nil
      end
      super
    end

    def rollback_transaction(*args)
      if @active_record_query_counter_transaction_start_time && open_transactions == 1
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ActiveRecordQueryCounter.add_transaction(@active_record_query_counter_transaction_start_time, end_time)
        ActiveRecordQueryCounter.increment_rollbacks
        @active_record_query_counter_transaction_start_time = nil
      end
      super
    end
  end
end
