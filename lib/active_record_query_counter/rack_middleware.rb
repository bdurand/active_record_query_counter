# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Rack middleware to count queries on a request.
  class RackMiddleware
    # @param app [Object] The Rack application.
    # @param thresholds [Hash] Options for the notification thresholds. Valid keys are:
    #   * `:query_time` - The minimum query time to send a notification for.
    #   * `:row_count` - The minimum row count to send a notification for.
    #   * `:transaction_time` - The minimum transaction time to send a notification for.
    #   * `:transaction_count` - The minimum transaction count to send a notification for.
    def initialize(app, thresholds: nil)
      @app = app
      @thresholds = thresholds.dup.freeze if thresholds
    end

    def call(env)
      ActiveRecordQueryCounter.count_queries do
        ActiveRecordQueryCounter.thresholds.set(@thresholds) if @thresholds

        @app.call(env)
      end
    end
  end
end
