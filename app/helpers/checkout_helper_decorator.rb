# frozen_string_literal: true

module CheckoutHelperDecorator
  SPL_SOURCE_TYPE = 'SPL'

  def spl_adjustment(line_item)
    line_item.adjustments.find_by('preferences LIKE ?', "%:external_source_type: #{SPL_SOURCE_TYPE}%")
  end

  def promotion_name(adjustment)
    if Spree::Spl.config.enhanced_discount_labels
      Spl::DiscountName.customer_label(
        adjustment.label,
        trade_agreement_number: adjustment.try(:preferred_trade_agreement_number)
      )
    else
      adjustment.label.split('.').last
    end
  end
end
