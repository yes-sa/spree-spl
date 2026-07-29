# frozen_string_literal: true

class PromotionSwitcherService
  include BooleanHelper

  SPL_RATE_LIMIT_ERRORS = %w[
    TOO_MANY_TRANSACTION_UPDATES
    REQUEST_ALREADY_PROCESSED
    OPERATION_IN_PROGRESS
  ].freeze

  def initialize(order, check_only)
    @check_only = check_only
    @line_items = order.line_items
    @order = order
  end

  def call
    if ::Spree::Spl.config.promotion_switcher_status_result
      call_with_status
    else
      call_legacy
    end
  end

  private

  attr_accessor :check_only, :line_items, :order

  def call_with_status
    apply_sparta_discount(order, check_only)
    :success
  rescue Spl::SpartaLoyaltyService::SplSendRequestError => e
    handle_spl_send_request_error(e)
  rescue StandardError => e
    handle_switcher_failure_status(e)
  end

  def call_legacy
    apply_sparta_discount(order, check_only)
  rescue StandardError => e
    Rails.logger.error("[PromotionSwitcher] Failed for Order #{order.id}: #{e.message}")
    remove_sparta_discount(order)
    order
  end

  def handle_spl_send_request_error(error)
    if spl_retriable_error?(error)
      Rails.logger.warn("[PromotionSwitcher] SPL skipped for Order #{order.id}: #{error.message}")
      return :rate_limited
    end

    handle_switcher_failure_status(error)
  end

  def handle_switcher_failure_status(error)
    Rails.logger.error("[PromotionSwitcher] Failed for Order #{order.id}: #{error.message}")
    remove_sparta_discount(order)
    :failed
  end

  def apply_sparta_discount(order, check_only)
    return unless order.line_items.any?

    spl_response = request_sparta_discount(order, check_only)
    return unless spl_response

    store_manual_coupon_results(order, spl_response)
    create_sparta_adjustments(spl_response, order)
  end

  def request_sparta_discount(order, check_only)
    Spl::SpartaLoyaltyService.new(
      spl_transaction_no(order),
      prepare_card_number_if_exist(order.public_metadata),
      order.line_items,
      DateTime.current,
      order.products,
      check_only,
      order.store,
      coupons: manual_coupons_for(order),
      shipping_amount: Spl::ShippingBasketLine.amount_for(order)
    ).call
  end

  def manual_coupons_for(order)
    return [] unless ::Spree::Spl.config.manual_discount_codes?

    Spl::ManualCoupons.for_order(order)
  end

  def store_manual_coupon_results(order, spl_response)
    return unless ::Spree::Spl.config.manual_discount_codes?

    Spl::ManualCoupons.store_sale_results!(order, spl_response.dig('response', 'coupons'))
  end

  def create_sparta_adjustments(spl_response, order)
    ApplySpartaDiscountService.new(spl_response, order).call
  end

  # Safer card-active lookup (string/symbol keys). Missing card number stays nil (legacy).
  def prepare_card_number_if_exist(metadata)
    meta = metadata.to_h.stringify_keys
    return '' unless cast_boolean(meta['spl_card_active'])

    meta['spl_no_card']
  end

  # Falls back to order.token when no custom tx number is set (legacy-compatible).
  def spl_transaction_no(order)
    order.private_metadata['spl_tx_no'].presence || order.token
  end

  def spl_retriable_error?(error)
    SPL_RATE_LIMIT_ERRORS.any? { |code| error.message.include?(code) }
  end

  def remove_sparta_discount(order)
    RemoveSpartaDiscountService.destroy_all_sparta_adjustments(order)
  end
end
