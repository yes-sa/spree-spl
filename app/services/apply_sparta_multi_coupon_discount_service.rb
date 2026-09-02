# frozen_string_literal: true

# Opt-in multi-coupon path (Spree::Spl.config.multi_coupon_adjustments = true).
# Default ApplySpartaDiscountService keeps the legacy single-adjustment behaviour.
class ApplySpartaMultiCouponDiscountService # rubocop:disable Metrics/ClassLength
  SPL_SOURCE_TYPE = 'SPL'

  def initialize(response, order)
    @basket = response['response']['basket']
    @line_items = order.line_items
    @order = order
    @response = response
  end

  def call
    line_items.each do |line_item|
      sparta_item = basket.find { |item| item['pos'].to_s == line_item.id.to_s }
      discounts = sparta_discounts_for(sparta_item)

      if discounts.empty?
        clear_spl_adjustments_for(line_item)
      else
        sync_spl_adjustments(line_item, discounts)
      end
    end
    sync_shipping_spl_adjustments
    RemoveSpartaDiscountService.destroy_not_spl_adjustments(order)
  end

  private

  attr_accessor :basket, :line_items, :order, :response

  def clear_spl_adjustments_for(line_item)
    adjustments = spl_adjustments_for(line_item)
    return if adjustments.blank?

    RemoveSpartaDiscountService.destroy_inactive_adjustments(adjustments, line_item, order)
  end

  def spl_adjustments_for(line_item)
    line_item.adjustments.where('preferences LIKE ?', "%:external_source_type: #{SPL_SOURCE_TYPE}%")
  end

  def sparta_discounts_for(sparta_item)
    return [] unless sparta_item
    return [] if sparta_item['discounts'].blank? || sparta_item['discountGross'].to_f.zero?

    sparta_item['discounts'].filter_map { |discount| build_discount_attrs(discount) }
  end

  def build_discount_attrs(discount)
    amount = discount['amount'].to_f
    return if amount.zero?

    external_name = discount['name'].to_s
    trade_agreement_number = external_name.split('.', 2).first
    {
      external_name: external_name,
      label: Spl::DiscountName.customer_label(external_name, trade_agreement_number: trade_agreement_number),
      trade_agreement_number: trade_agreement_number,
      amount: -amount.abs
    }
  end

  def sync_spl_adjustments(line_item, discounts)
    existing = spl_adjustments_for(line_item).to_a
    wanted_names = discounts.pluck(:external_name)

    stale = existing.reject { |adjustment| wanted_names.include?(adjustment.preferred_external_name) }
    remove_stale_adjustments(line_item, stale)

    discounts.each do |discount|
      adjustment = existing.find do |existing_adjustment|
        !existing_adjustment.destroyed? && existing_adjustment.preferred_external_name == discount[:external_name]
      end

      if adjustment
        update_spl_adjustment(adjustment, discount, line_item)
      else
        create_spl_adjustment(line_item, discount)
      end
    end
  end

  def remove_stale_adjustments(line_item, stale)
    return if stale.empty?

    relation = line_item.adjustments.where(id: stale.map(&:id))
    RemoveSpartaDiscountService.destroy_inactive_adjustments(relation, line_item, order)
  end

  def update_spl_adjustment(adjustment, discount, line_item)
    return if adjustment.amount == discount[:amount] && adjustment.label == discount[:label]

    adjustment.update(amount: discount[:amount], label: discount[:label])
    recalculate(line_item)
  end

  def create_spl_adjustment(line_item, discount)
    line_item.adjustments.create(
      adjustable: line_item,
      amount: discount[:amount],
      included: false,
      label: discount[:label],
      order: order,
      preferred_external_source_type: SPL_SOURCE_TYPE,
      preferred_trade_agreement_number: discount[:trade_agreement_number],
      preferred_external_name: discount[:external_name]
    )
    recalculate(line_item)
  end

  def recalculate(line_item)
    Spree::Dependencies.cart_recalculate_service.constantize.call(order: order, line_item: line_item)
  end

  def sync_shipping_spl_adjustments
    return unless Spl::ShippingBasketLine.enabled?

    shipment = order.shipments.first
    shipping_item = basket.find { |item| Spl::ShippingBasketLine.shipping_pos?(item['pos']) }
    discounts = sparta_discounts_for(shipping_item)

    return log_missing_shipment(discounts) unless shipment

    if discounts.empty?
      clear_spl_adjustments_for_shipment(shipment)
    else
      sync_spl_adjustments_for_shipment(shipment, discounts)
    end
  end

  def log_missing_shipment(discounts)
    return if discounts.empty?

    Rails.logger.info(
      "[SPL] Shipping discounts returned but order #{order.id} has no shipment yet; skipping apply"
    )
  end

  def clear_spl_adjustments_for_shipment(shipment)
    adjustments = spl_adjustments_for_shipment(shipment)
    return if adjustments.blank?

    RemoveSpartaDiscountService.destroy_shipment_spl_adjustments(shipment, order)
  end

  def spl_adjustments_for_shipment(shipment)
    shipment.adjustments.where('preferences LIKE ?', "%:external_source_type: #{SPL_SOURCE_TYPE}%")
  end

  def sync_spl_adjustments_for_shipment(shipment, discounts)
    existing = spl_adjustments_for_shipment(shipment).to_a
    wanted_names = discounts.pluck(:external_name)

    stale = existing.reject { |adjustment| wanted_names.include?(adjustment.preferred_external_name) }
    remove_stale_shipment_adjustments(shipment, stale)

    discounts.each do |discount|
      adjustment = find_shipment_adjustment(existing, discount[:external_name])
      if adjustment
        update_spl_shipment_adjustment(adjustment, discount, shipment)
      else
        create_spl_shipment_adjustment(shipment, discount)
      end
    end

    order.updater.update
  end

  def find_shipment_adjustment(existing, external_name)
    existing.find do |adjustment|
      !adjustment.destroyed? && adjustment.preferred_external_name == external_name
    end
  end

  def remove_stale_shipment_adjustments(shipment, stale)
    return if stale.empty?

    shipment.adjustments.where(id: stale.map(&:id)).destroy_all
    ::Spree::Adjustable::AdjustmentsUpdater.update(shipment)
  end

  def update_spl_shipment_adjustment(adjustment, discount, shipment)
    return if adjustment.amount == discount[:amount] && adjustment.label == discount[:label]

    adjustment.update(amount: discount[:amount], label: discount[:label])
    ::Spree::Adjustable::AdjustmentsUpdater.update(shipment)
  end

  def create_spl_shipment_adjustment(shipment, discount)
    shipment.adjustments.create(
      adjustable: shipment,
      amount: discount[:amount],
      included: false,
      label: discount[:label],
      order: order,
      preferred_external_source_type: SPL_SOURCE_TYPE,
      preferred_trade_agreement_number: discount[:trade_agreement_number],
      preferred_external_name: discount[:external_name]
    )
    ::Spree::Adjustable::AdjustmentsUpdater.update(shipment)
  end
end
