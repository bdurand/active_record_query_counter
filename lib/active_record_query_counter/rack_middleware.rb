# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Rack middleware to count queries on a request.
  class RackMiddleware
    def initialize(app, query_time_threshold: nil, row_count_threshold: nil, transaction_time_threshold: nil, transaction_count_threshold: nil)
      @app = app
      @query_time_threshold = query_time_threshold
      @row_count_threshold = row_count_threshold
      @transaction_time_threshold = transaction_time_threshold
      @transaction_count_threshold = transaction_count_threshold
    end

    def call(env)
      ActiveRecordQueryCounter.count_queries do
        thresholds = ActiveRecordQueryCounter.thresholds
        thresholds.query_time = @query_time_threshold if @query_time_threshold
        thresholds.row_count = @row_count_threshold if @row_count_threshold
        thresholds.transaction_time = @transaction_time_threshold if @transaction_time_threshold
        thresholds.transaction_count = @transaction_count_threshold if @transaction_count_threshold

        @app.call(env)
      end
    end
  end
end
