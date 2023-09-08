# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Sidekiq middleware to count queries on a job.
  #
  # Notification thresholds can be set per worker with the `active_record_query_counter.thresholds` key in the
  # `sidekiq_options` hash. Valid keys are:
  # * `:query_time` - The minimum query time to send a notification for.
  # * `:row_count` - The minimum row count to send a notification for.
  # * `:transaction_time` - The minimum transaction time to send a notification for.
  # * `:transaction_count` - The minimum transaction count to send a notification for.
  #
  # Thresholds can be disabled for a worker by setting `active_record_query_counter.thresholds` to `false`.
  #
  # @example
  #
  #   class MyWorker
  #     include Sidekiq::Worker
  #
  #     sidekiq_options active_record_query_counter: {thresholds: {query_time: 1.5}}
  #
  #     def perform
  #       # ...
  #     end
  #   end
  class SidekiqMiddleware
    if defined?(Sidekiq::ServerMiddleware)
      include Sidekiq::ServerMiddleware
    end

    def call(job_instance, job_payload, queue)
      ActiveRecordQueryCounter.count_queries do
        thresholds = job_payload.dig("active_record_query_counter", "thresholds")
        if thresholds.is_a?(Hash)
          ActiveRecordQueryCounter.thresholds.set(thresholds)
        elsif thresholds == false
          ActiveRecordQueryCounter.thresholds.clear
        end

        yield
      end
    end
  end
end
