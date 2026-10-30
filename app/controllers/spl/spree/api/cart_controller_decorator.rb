# frozen_string_literal: true

module Spl
  module Spree
    module Api
      module CartControllerDecorator
        include BooleanHelper

        # The card used to be merged into the create params; a metafield needs
        # the cart to exist, so it is stamped on right after `super` instead.
        def create
          super

          add_spl_discount_params_to_order(spree_current_user)
        end

        def show
          promotion_switcher(spree_current_order, true)

          super
        end

        def update_spl_card_activate # rubocop:disable Metrics/AbcSize
          spree_authorize! :update, spree_current_order, order_token

          if params.dig('spl', 'card_active').nil?
            spree_current_order.errors.add(:base, I18n.t('order.loyalty_card_missing'))
            render_error_payload(spree_current_order.errors)
          else
            active_param = cast_boolean(params.dig('spl', 'card_active'))
            update_spl_card_active_param(spree_current_order, active_param)
            spree_current_order.reload
            promotion_switcher(spree_current_order, true)

            render_serialized_payload { serialized_current_order }
          end
        end

        private

        def promotion_switcher(order, check_only)
          PromotionSwitcherService.new(order, check_only).call
        end

        def update_spl_card_active_param(order, active_param)
          ::Spl::Metafields.set_card_active(order, active_param)
          order.promotions.destroy_all if order.promotions.any?
        end

        def add_spl_discount_params_to_order(user)
          return unless ::Spl::Metafields.card_number?(user) && ::Spl::Metafields.card_active_set?(user)

          order = spree_current_order
          return if order.nil?

          ::Spl::Metafields.set_card_active(order, ::Spl::Metafields.card_active?(user))
          ::Spl::Metafields.set_card_number(order, ::Spl::Metafields.card_number(user))
        end

        def switch_spl_active_param(order, check_only)
          return if user.nil?
          return unless ::Spl::Metafields.card_active_set?(order)

          if ::Spl::Metafields.card_active(order) == true
            ::Spl::Metafields.set_card_active(order, false)
          else
            ::Spl::Metafields.set_card_active(order, true)
          end

          promotion_switcher(order, check_only)
        end

        def assign_spl_active_param(order, user)
          return unless ::Spl::Metafields.card_active_set?(user)

          ::Spl::Metafields.set_card_active(order, ::Spl::Metafields.card_active?(user))
          ::Spl::Metafields.set_card_number(order, ::Spl::Metafields.card_number(user))
        end

        def maintain_spl_adjustments(order)
          return unless ::Spl::Metafields.card_active_set?(order)

          ::Spl::Metafields.set_card_active(order, true)
          promotion_switcher(order, true)
        end
      end
    end
  end
end
