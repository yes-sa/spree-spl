# frozen_string_literal: true

module Spl
  # Typed marketing / promo codes stored on the order and sent as sale `coupons[]`.
  # SPL decides validity, stacking, and exclusion — Spree never evaluates the code.
  module ManualCoupons
    METADATA_KEY = 'spl_manual_coupons'
    LAST_RESULTS_KEY = 'spl_last_sale_coupons'
    CODE_FORMAT = /\A[A-Z0-9]+\z/

    module_function

    def for_order(order)
      Array(order&.private_metadata&.[](METADATA_KEY)).map { |code| normalize(code) }.compact_blank.uniq
    end

    def normalize(code)
      code.to_s.strip.upcase.presence
    end

    def valid_format?(code)
      normalized = normalize(code)
      normalized.present? && normalized.match?(CODE_FORMAT)
    end

    def set!(order, codes)
      normalized = Array(codes).map { |code| normalize(code) }.compact_blank.uniq
      metadata = (order.private_metadata || {}).stringify_keys
      order.update!(private_metadata: metadata.merge(METADATA_KEY => normalized))
      normalized
    end

    def add!(order, code)
      set!(order, for_order(order) + [code])
    end

    def replace!(order, code)
      set!(order, [code])
    end

    def remove!(order, code = nil)
      if code.nil?
        set!(order, [])
      else
        normalized = normalize(code)
        set!(order, for_order(order) - [normalized])
      end
    end

    def store_sale_results!(order, coupons_payload)
      metadata = (order.private_metadata || {}).stringify_keys
      order.update!(private_metadata: metadata.merge(LAST_RESULTS_KEY => Array(coupons_payload)))
    end

    def last_sale_results(order)
      Array(order&.private_metadata&.[](LAST_RESULTS_KEY))
    end

    def result_for(order, code)
      normalized = normalize(code)
      last_sale_results(order).find { |entry| normalize(entry['code'] || entry[:code]) == normalized }
    end
  end
end
