# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Thresholds for sending notifications based on query time, row count, transaction time, and
  # transaction count.
  class Thresholds
    attr_reader :query_time, :row_count, :transaction_time, :transaction_count

    def query_time=(value)
      @query_time = value&.to_f
    end

    def row_count=(value)
      @row_count = value&.to_i
    end

    def transaction_time=(value)
      @transaction_time = value&.to_f
    end

    def transaction_count=(value)
      @transaction_count = value&.to_i
    end

    def attributes=(attributes)
      attributes.each do |key, value|
        public_send("#{key}=", value)
      end
    end
  end
end
