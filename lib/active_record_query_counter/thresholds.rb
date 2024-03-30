# frozen_string_literal: true

module ActiveRecordQueryCounter
  # Thresholds for sending notifications based on query time, row count, transaction time, and
  # transaction count.
  class Thresholds
    attr_reader :query_time, :row_count, :transaction_time, :transaction_count

    def initialize
      clear
    end

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

    # Set threshold values from a hash.
    #
    # @param attributes [Hash] the attributes to set
    # @return [void]
    def set(values)
      values.each do |key, value|
        setter = "#{key}="
        if respond_to?(setter)
          public_send(:"#{key}=", value)
        else
          raise ArgumentError, "Unknown threshold: #{key}"
        end
      end
    end

    # Clear all threshold values.
    def clear
      @query_time = nil
      @row_count = nil
      @transaction_time = nil
      @transaction_count = nil
    end
  end
end
