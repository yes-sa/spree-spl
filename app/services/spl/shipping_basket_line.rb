# frozen_string_literal: true

module Spl
  # Optional delivery row for SPL /api/tx/sale baskets.
  # Disabled unless Spree::Spl.config.shipping_product_code is set by the host app.
  class ShippingBasketLine
    class << self
      def enabled?
        ::Spree::Spl.config.shipping_basket_line_enabled?
      end

      def product_code
        ::Spree::Spl.config.shipping_product_code
      end

      def pos
        ::Spree::Spl.config.shipping_basket_pos
      end

      def amount_for(order)
        return unless enabled?
        # Only include shipping when Spree has a shipment we can attach SPL
        # adjustments to. Estimated cart shipping without a shipment would make
        # SPL return delivery discounts we then skip — wiping product discounts.
        return unless order&.shipments&.any?

        resolver = ::Spree::Spl.config.shipping_amount_resolver
        amount = resolver ? resolver.call(order) : default_amount_for(order)
        amount = amount.to_d if amount
        # Zero-cost shipments (unset rates / free placeholders) must not be sent —
        # amountGross: 0 on the delivery line breaks product coupon application in SPL.
        return if amount.nil? || !amount.positive?

        amount
      end

      def basket_item(amount)
        {
          pos: pos,
          quantity: 1,
          productCode: product_code,
          amountGross: amount.to_f,
          notPromoted: false
        }
      end

      def shipping_pos?(value)
        return false unless enabled?

        value.to_s == pos.to_s
      end

      def default_amount_for(order)
        return unless order

        shipment = order.shipments.to_a.find { |s| s.cost.to_d.positive? } || order.shipments.first
        return shipment.cost.to_d if shipment&.cost

        total = order.shipment_total.to_d
        total.positive? ? total : nil
      end
    end
  end
end
