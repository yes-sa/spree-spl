# frozen_string_literal: true

module Spl
  module ManualCoupons
    class RemoveService
      Result = Struct.new(:success, :code, keyword_init: true) do
        def success?
          success
        end
      end

      def initialize(order, code = nil, user: order&.user, store: order&.store)
        @order = order
        @code = code
        @user = user
        @store = store
      end

      def call
        return Result.new(success: false, code: nil) unless ::Spree::Spl.config.manual_discount_codes?

        normalized = @code.present? ? ManualCoupons.normalize(@code) : nil
        ManualCoupons.remove!(@order, normalized)
        RemoveSpartaDiscountService.destroy_all_sparta_adjustments(@order)
        RecalculateOrderService.bump_coupon_version!(@order)
        RecalculateOrderService.new(
          @order.reload,
          user: @user,
          store: @store,
          force: true
        ).call

        Result.new(success: true, code: normalized)
      end
    end
  end
end
