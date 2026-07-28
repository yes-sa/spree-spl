# frozen_string_literal: true

module Spree
  module Spl
    class Configuration
      # Opt-in flags. Defaults preserve historical gem behaviour for other apps.
      attr_accessor :error_reporter,
                    :multi_coupon_adjustments,
                    :basket_amount_gross,
                    :reprice_on_coupon_change,
                    :promotion_switcher_status_result,
                    :enhanced_discount_labels

      def initialize
        @error_reporter = ->(message, extra = {}) { Rails.logger.warn("[SPL] #{message} #{extra.inspect}") }
        @multi_coupon_adjustments = false
        @basket_amount_gross = :unit_price # :unit_price | :line_total
        @reprice_on_coupon_change = false
        @promotion_switcher_status_result = false
        @enhanced_discount_labels = false
      end
    end

    def self.config = (@config ||= Configuration.new)
    def self.configure = yield(config)

    def self.report_error(message, extra = {})
      config.error_reporter&.call(message, extra)
    rescue StandardError => e
      Rails.logger.error("[SPL] error_reporter failed: #{e.class}: #{e.message}")
    end
  end
end
