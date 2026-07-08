# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Extension to ActiveRecord::ConnectionAdapters::TransactionManager to count transactions.
  module TransactionManagerExtension
    # Extension to ActiveRecord::ConnectionAdapters::RealTransaction to capture the time when
    # the COMMIT or ROLLBACK statement finishes. The transaction manager runs the after commit
    # and after rollback callbacks before returning, so this is the only place where the end
    # of the database transaction itself can be observed.
    module TransactionExtension
      attr_reader :active_record_query_counter_end_time

      def commit
        super
      ensure
        @active_record_query_counter_end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def rollback
        super
      ensure
        @active_record_query_counter_end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    class << self
      def inject(transaction_manager_class)
        unless transaction_manager_class.include?(self)
          transaction_manager_class.prepend(self)
        end

        real_transaction_class = ActiveRecord::ConnectionAdapters::RealTransaction
        unless real_transaction_class.include?(TransactionExtension)
          real_transaction_class.prepend(TransactionExtension)
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
      transaction = ((start_time && open_transactions == 1) ? current_transaction : nil)

      retval = super

      if transaction
        ActiveRecordQueryCounter.add_transaction(start_time, active_record_query_counter_end_time(transaction))
        @active_record_query_counter_transaction_start_time = nil
      end

      retval
    end

    def rollback_transaction(*args)
      # open_transactions is 0 here when a failed COMMIT already popped the transaction off
      # the stack; the start time still being set identifies it as the outermost transaction.
      start_time = @active_record_query_counter_transaction_start_time
      transaction = ((start_time && open_transactions <= 1) ? (args.first || current_transaction) : nil)

      super
    ensure
      # Recorded even if the ROLLBACK itself raises (e.g. the connection died) since the
      # transaction is over either way.
      if transaction
        ActiveRecordQueryCounter.add_transaction(start_time, active_record_query_counter_end_time(transaction))
        ActiveRecordQueryCounter.increment_rollbacks
        @active_record_query_counter_transaction_start_time = nil
      end
    end

    private

    # The time when the transaction's COMMIT or ROLLBACK finished, excluding any time spent
    # in after commit or after rollback callbacks. Falls back to the current time if the
    # transaction did not record one.
    def active_record_query_counter_end_time(transaction)
      end_time = nil
      if transaction.respond_to?(:active_record_query_counter_end_time)
        end_time = transaction.active_record_query_counter_end_time
      end
      end_time || Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
