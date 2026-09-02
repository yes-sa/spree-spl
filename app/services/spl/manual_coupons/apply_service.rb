# frozen_string_literal: true

module Spl
  module ManualCoupons
    class ApplyService
      Result = Struct.new(:success, :code, :error_key, :non_valid_reasons, keyword_init: true) do
        def success?
          success
        end
      end

      def initialize(order, code, user: order&.user, store: order&.store)
        @order = order
        @code = code
        @user = user
        @store = store
      end

      def call
        return failure(nil, 'disabled') unless ::Spree::Spl.config.manual_discount_codes?

        normalized = ManualCoupons.normalize(@code)
        return failure(normalized, 'blank') if normalized.blank?
        return failure(normalized, 'invalid_format') unless ManualCoupons.valid_format?(normalized)

        ManualCoupons.replace!(@order, normalized)
        recalculate!

        invalid = reject_invalid_coupon(normalized)
        return invalid if invalid

        # SPL may omit coupons[] for some codes that still apply as basket discounts.
        # Keep the code when sale succeeded and no explicit invalid flag was returned.
        Result.new(success: true, code: normalized, error_key: nil, non_valid_reasons: [])
      end

      private

      def reject_invalid_coupon(normalized)
        coupon_result = ManualCoupons.result_for(@order.reload, normalized)
        return if coupon_result.blank?

        result = coupon_result.stringify_keys
        return unless false?(result['valid'])

        ManualCoupons.remove!(@order, normalized)
        recalculate!
        failure(normalized, 'not_valid', Array(result['nonValidReasons']))
      end

      def recalculate!
        RemoveSpartaDiscountService.destroy_all_sparta_adjustments(@order)
        RecalculateOrderService.bump_coupon_version!(@order)
        RecalculateOrderService.new(
          @order.reload,
          user: @user,
          store: @store,
          force: true
        ).call
      end

      def failure(code, error_key, reasons = [])
        Result.new(success: false, code: code, error_key: error_key, non_valid_reasons: reasons)
      end

      def false?(value)
        value == false || value.to_s == 'false'
      end
    end
  end
end
