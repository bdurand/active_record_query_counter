# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Rack middleware to count queries on a request.
  class RackMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      ActiveRecordQueryCounter.count_queries { @app.call(env) }
    end
  end
end
