# frozen_string_literal: true

module CartDecorator
  private

  def order_spl?
    if ::Spl::Metafields.card_number?(order) && ::Spl::Metafields.card_active_set?(order)
      ::Spl::Metafields.card_active(order)
    else
      false
    end
  end
end
