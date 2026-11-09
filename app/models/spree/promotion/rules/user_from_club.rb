# frozen_string_literal: true

module Spree
  class Promotion
    module Rules
      class UserFromClub < PromotionRule
        def applicable?(promotable)
          promotable.is_a?(Spree::Order)
        end

        def eligible?(order, _options = {})
          unless user_card_active?(order) && user_card_valid?(order)
            eligibility_errors.add(:base, eligibility_error_message(:no_user_specified))
          end
          eligibility_errors.empty?
        end

        private

        def user_card_active?(order)
          return false if order.user.nil?

          ::Spl::Metafields.card_active(order.user) == true
        end

        def user_card_valid?(order)
          ::Spl::ValidateCardService.new(::Spl::Metafields.card_number(order.user), order.user, order.store).call
        end
      end
    end
  end
end
