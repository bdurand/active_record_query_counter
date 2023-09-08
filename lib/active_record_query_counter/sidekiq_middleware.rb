# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Sidekiq middleware to count queries on a job.
  class SidekiqMiddleware
    def call(worker, job, queue, &block)
      ActiveRecordQueryCounter.count_queries(&block)
    end
  end
end
