# frozen_string_literal: true

class PromotionSwitcherService
  def initialize(order, check_only)
    @check_only = check_only
    @line_items = order.line_items
    @order = order
  end

  def call
    apply_sparta_discount(order, check_only)
  rescue StandardError => e
    Rails.logger.error("[PromotionSwitcher] Failed for Order #{order.id}: #{e.message}")
    remove_sparta_discount(order)
    order
  end

  private

  attr_accessor :check_only, :line_items, :order

  def apply_sparta_discount(order, check_only)
    return unless order.line_items.any?

    card_number = prepare_card_number_if_exist(order)
    spl_response = Spl::SpartaLoyaltyService.new(order.token,
                                                 card_number,
                                                 order.line_items,
                                                 DateTime.current,
                                                 order.products,
                                                 check_only,
                                                 order.store).call
    return unless spl_response

    create_sparta_adjustments(spl_response, order)
  end

  def create_sparta_adjustments(spl_response, order)
    ApplySpartaDiscountService.new(spl_response, order).call
  end

  def prepare_card_number_if_exist(order)
    ::Spl::Metafields.card_active?(order) ? ::Spl::Metafields.card_number(order) : ''
  end
end
