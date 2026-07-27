# frozen_string_literal: true

class ApplySpartaDiscountService
  SPL_SOURCE_TYPE = 'SPL'

  def initialize(response, order)
    @basket = response['response']['basket']
    @line_items = order.line_items
    @order = order
    @response = response
  end

  def call
    return unless response_valid?
    return ApplySpartaMultiCouponDiscountService.new(response, order).call if Spree::Spl.config.multi_coupon_adjustments

    apply_legacy_adjustments
  end

  private

  attr_accessor :basket, :line_items, :order, :response

  def response_valid?
    response['errorCode'] == '0' && response['response'].present? && response['response']['basket'].present?
  end

  def apply_legacy_adjustments # rubocop:disable Metrics/AbcSize
    line_items.each do |line_item|
      sparta_item = basket.find { |i| i['pos'] == line_item['id'] }
      spl_adjustment_present_and_spl_discounts_nil?(sparta_item, line_item)
      next if sparta_item['discounts'].nil?

      label = sparta_item&.fetch('discounts')&.first&.fetch('name')&.split('. ')&.last
      preferences(sparta_item:)
      amount = -sparta_item&.fetch('discountGross') # Negative value for discount
      discounts_present?(line_item, label)
      update_sparta_adjustment(line_item, label, amount)
      create_sparta_adjustment(order, amount, label, line_item)
    end
    RemoveSpartaDiscountService.destroy_not_spl_adjustments(order)
  end

  def spl_adjustment_present_and_spl_discounts_nil?(sparta_item, line_item)
    unless sparta_item['discounts'].nil? &&
           line_item.adjustments.any? { |a| a.preferred_external_source_type == SPL_SOURCE_TYPE }
      return false
    end

    adjustments = line_item.adjustments.where('preferences LIKE ?', "%:external_source_type: #{SPL_SOURCE_TYPE}%")
    RemoveSpartaDiscountService.destroy_inactive_adjustments(adjustments, line_item, order)
  end

  def discounts_present?(line_item, label)
    adjustments = line_item.adjustments.select { |a| a.preferred_external_source_type == SPL_SOURCE_TYPE }
    return if adjustments.blank? # rubocop:disable Style/ReturnNilInPredicateMethodDefinition

    existing_labels = adjustments.pluck(:label)
    return if existing_labels.include?(label) # rubocop:disable Style/ReturnNilInPredicateMethodDefinition

    RemoveSpartaDiscountService.destroy_inactive_adjustments(adjustments, line_item, order)
  end

  def create_sparta_adjustment(order, amount, label, line_item)
    return if amount.zero? || line_item.adjustments.find_by(label: label, amount: amount).present?

    line_item.adjustments.create(
      adjustable: line_item,
      amount: amount,
      included: false,
      label: label,
      order: order,
      **preferences
    )

    Spree::Dependencies.cart_recalculate_service.constantize.call(order: order, line_item: line_item)
  end

  def update_sparta_adjustment(line_item, label, amount)
    adjustments = line_item.adjustments
    return if amount.zero? || adjustments.find_by(label: label).nil?
    return if adjustments.find_by(label: label, amount: amount).present?

    adjustments.find_by(label: label).update(amount: amount)
  end

  def preferences(sparta_item: nil)
    external_name = sparta_item&.fetch('discounts')&.first&.fetch('name')
    trade_agreement_number = external_name&.split('.')&.first

    @preferences ||= {
      preferred_external_source_type: SPL_SOURCE_TYPE,
      preferred_trade_agreement_number: trade_agreement_number,
      preferred_external_name: external_name
    }
  end
end
