# frozen_string_literal: true

module OrderUpdaterDecorator
  private

  def perform_update_sparta_state_job # rubocop:disable Metrics/AbcSize
    UpdateSpartaStateJob.perform_later(order.token, 'D', order.number, order.store) if order.payment_state == 'paid'
    UpdateSpartaStateJob.perform_later(order.token, 'C', order.number, order.store) if order.state == 'canceled'
  end

  def check_spl_adjustments
    if ::Spl::Metafields.card_active(order) == true
      updated_any_adjustment = false
      order.adjustments.each do |adjustment|
        if adjustment.preferred_external_source_type != 'SPL' && adjustment.eligible?
          adjustment.update(eligible: false)
          updated_any_adjustment = true
        end
      end
      updated_any_adjustment
    else
      false
    end
  end
end
