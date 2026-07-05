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
      # The outermost check must happen before calling super because super pops the
      # transaction stack. The transaction is only recorded after super succeeds; if the
      # COMMIT raises, the start time is left in place so the rollback that Rails performs
      # next is counted as a rollback rather than a successful commit.
      start_time = @active_record_query_counter_transaction_start_time
      committing = (start_time && open_transactions == 1)

      retval = super

      if committing
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ActiveRecordQueryCounter.add_transaction(start_time, end_time)
        @active_record_query_counter_transaction_start_time = nil
      end

      retval
    end

    def rollback_transaction(*args)
      # open_transactions is 0 here when a failed COMMIT already popped the transaction off
      # the stack; the start time still being set identifies it as the outermost transaction.
      start_time = @active_record_query_counter_transaction_start_time
      rolling_back = (start_time && open_transactions <= 1)

      super
    ensure
      # Recorded even if the ROLLBACK itself raises (e.g. the connection died) since the
      # transaction is over either way.
      if rolling_back
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ActiveRecordQueryCounter.add_transaction(start_time, end_time)
        ActiveRecordQueryCounter.increment_rollbacks
        @active_record_query_counter_transaction_start_time = nil
      end
    end
  end
end
