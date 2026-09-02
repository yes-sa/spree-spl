# frozen_string_literal: true

class RemoveSpartaDiscountService
  SPL_SOURCE_TYPE = 'SPL'

  def self.destroy_all_sparta_adjustments(order)
    order.line_items.each do |line_item|
      next unless line_item.adjustments.any? { |adj| adj.preferred_external_source_type == SPL_SOURCE_TYPE }

      adjustments = line_item.adjustments.where('preferences LIKE ?', "%:external_source_type: #{SPL_SOURCE_TYPE}%")
      destroy_adjustments(adjustments, line_item, order)

      adjustments.where('preferences LIKE ?', "%:external_source_type: #{SPL_SOURCE_TYPE}%").destroy_all
    end

    return unless Spl::ShippingBasketLine.enabled?

    order.shipments.each do |shipment|
      destroy_shipment_spl_adjustments(shipment, order)
    end
  end

  def self.destroy_shipment_spl_adjustments(shipment, order)
    adjustments = shipment.adjustments.where('preferences LIKE ?', "%:external_source_type: #{SPL_SOURCE_TYPE}%")
    return if adjustments.blank?

    adjustments.destroy_all
    ::Spree::Adjustable::AdjustmentsUpdater.update(shipment)
    order.updater.update
  end

  def self.destroy_inactive_adjustments(adjustments, line_item, order)
    destroy_adjustments(adjustments, line_item, order)
    adjustments.where(eligible: true).update_all(eligible: false, state: 'closed')

    line_item.reload
    ::Spree::Dependencies.cart_recalculate_service.constantize.call(order: order, line_item: line_item)

    adjustments.destroy_all
  end

  def self.destroy_not_spl_adjustments(order)
    return unless order.line_items.any? { |line_item| line_item.adjustments.any? { |adj| adj.preferred_external_source_type == SPL_SOURCE_TYPE } }

    order.line_items.each do |line_item|
      adjustments_to_remove = line_item.adjustments.reject { |adj| adj.preferred_external_source_type == SPL_SOURCE_TYPE }
      adjustments_to_remove.each(&:destroy)
    end
  end

  private_class_method def self.destroy_adjustments(adjustments, line_item, order)
    adjustments.where(eligible: true).update_all(eligible: false, state: 'closed')

    line_item.reload
    ::Spree::Dependencies.cart_recalculate_service.constantize.call(order: order, line_item: line_item)
  end
end
