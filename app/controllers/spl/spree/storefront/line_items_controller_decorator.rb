# frozen_string_literal: true

module Spl
  module Spree
    module Storefront
      module LineItemsControllerDecorator
        def self.prepended(base)
          base.before_action :add_spl_discount_params_to_order, only: :create
        end

        private

        def add_spl_discount_params_to_order
          user = spree_current_user
          return unless ::Spl::Metafields.card_number?(user) && ::Spl::Metafields.card_active_set?(user)

          order = current_order(create_order_if_necessary: true)
          ::Spl::Metafields.set_card_number(order, ::Spl::Metafields.card_number(user))
          ::Spl::Metafields.set_card_active(order, ::Spl::Metafields.card_active?(user))
        end
      end
    end
  end
end
