# frozen_string_literal: true

module Spl
  # Reprices an order against SPL/Sparta after cart or coupon changes.
  # Syncs card metadata from the user, clears coupon cache, short-circuits on an
  # unchanged basket fingerprint (unless +force+), then runs PromotionSwitcherService
  # (with a rate-limit retry that bumps the SPL transaction number).
  class RecalculateOrderService
    FINGERPRINT_KEY = 'spl_basket_fingerprint'

    def initialize(order, user: order&.user, store: order&.store, force: false)
      @order = order
      @user = user
      @store = store
      @force = force
    end

    def call
      return unless @order&.persisted?
      return unless @order.line_items.exists?

      Spl::SyncOrderMetadataService.new(@order, @user).call if @user
      clear_coupons_cache

      fingerprint = basket_fingerprint
      return @order.reload if !@force && fingerprint == stored_fingerprint

      store_fingerprint(fingerprint) if run_promotion_switcher == :success
      @order.reload
    end

    def self.bump_coupon_version!(order)
      metadata = (order.private_metadata || {}).stringify_keys
      version = metadata['spl_coupon_version'].to_i + 1
      order.update!(private_metadata: metadata.merge('spl_coupon_version' => version))
    end

    private

    def run_promotion_switcher
      result = PromotionSwitcherService.new(@order, true).call
      return result unless result == :rate_limited

      bump_transaction_number!
      PromotionSwitcherService.new(@order.reload, true).call
    end

    def basket_fingerprint
      fingerprint_parts = [
        line_item_fingerprint_parts,
        @order.public_metadata.slice('spl_no_card', 'spl_card_active'),
        @order.private_metadata['spl_coupon_version']
      ]
      fingerprint_parts << ManualCoupons.for_order(@order) if ::Spree::Spl.config.manual_discount_codes?
      fingerprint_parts << ShippingBasketLine.amount_for(@order) if ShippingBasketLine.enabled?

      Digest::SHA256.hexdigest(fingerprint_parts.to_json)
    end

    def line_item_fingerprint_parts
      @order.line_items.order(:id).map do |line_item|
        [line_item.id, line_item.variant_id, line_item.quantity, line_item.amount.to_d]
      end
    end

    def stored_fingerprint
      @order.private_metadata[FINGERPRINT_KEY]
    end

    def store_fingerprint(fingerprint)
      metadata = (@order.private_metadata || {}).stringify_keys.merge(FINGERPRINT_KEY => fingerprint)
      @order.update!(private_metadata: metadata)
    end

    def clear_coupons_cache
      return unless @user

      Rails.cache.delete("user_#{@user.id}_spl_coupons")
      return unless @store

      Rails.cache.delete("user_#{@user.id}_spl_coupons_store_#{@store.id}")
    end

    def bump_transaction_number!
      metadata = (@order.private_metadata || {}).stringify_keys
      attempt = metadata['spl_tx_attempt'].to_i + 1
      @order.update!(
        private_metadata: metadata.merge(
          'spl_tx_attempt' => attempt,
          'spl_tx_no' => "#{@order.token}-#{attempt}"
        )
      )
    end
  end
end
