# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Sidekiq middleware to count queries on a job.
  class SidekiqMiddleware
    if defined?(Sidekiq::ServerMiddleware)
      include Sidekiq::ServerMiddleware
    end

    def call(job_instance, job_payload, queue)
      ActiveRecordQueryCounter.count_queries do
        options = job_payload["active_record_query_counter"]
        if options.is_a?(Hash)
          thresholds = ActiveRecordQueryCounter.thresholds
          thresholds.query_time = options["query_time_threshold"] if options.key?("query_time_threshold")
          thresholds.row_count = options["row_count_threshold"] if options.key?("row_count_threshold")
          thresholds.transaction_time = options["transaction_time_threshold"] if options.key?("transaction_time_threshold")
          thresholds.transaction_count = options["transaction_count_threshold"] if options.key?("transaction_count_threshold")
        end

        yield
      end
    end
  end
end
