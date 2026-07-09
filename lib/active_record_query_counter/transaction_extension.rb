# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Extension to ActiveRecord::ConnectionAdapters::RealTransaction to count transactions.
  # Real transactions are always the outermost database transaction; savepoint transactions
  # nested inside them are considered part of the transaction and are not counted separately.
  module TransactionExtension
    class << self
      def inject(transaction_class)
        unless transaction_class.include?(self)
          transaction_class.prepend(self)
        end
      end
    end

    def initialize(...)
      super
      @active_record_query_counter_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def commit
      # The transaction is only recorded after the COMMIT succeeds. If it raises, the start
      # time is left in place so the rollback that Rails performs next is counted as a
      # rollback rather than a successful commit. Recording here rather than in the
      # transaction manager keeps time spent in after commit callbacks (which run after this
      # method returns) out of the transaction time.
      retval = super
      active_record_query_counter_record_transaction
      retval
    end

    def rollback
      super
    ensure
      # Recorded even if the ROLLBACK itself raises (e.g. the connection died) since the
      # transaction is over either way.
      active_record_query_counter_record_transaction(rollback: true)
    end

    private

    def active_record_query_counter_record_transaction(rollback: false)
      start_time = @active_record_query_counter_start_time
      return unless start_time

      @active_record_query_counter_start_time = nil
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ActiveRecordQueryCounter.add_transaction(start_time, end_time)
      ActiveRecordQueryCounter.increment_rollbacks if rollback
    end
  end
end
