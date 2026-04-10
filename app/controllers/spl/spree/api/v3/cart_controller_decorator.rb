# frozen_string_literal: true

module Spl
  module Spree
    module Api
      module V3
        module CartControllerDecorator
          include BooleanHelper

          def create
            add_spl_discount_params_to_order(current_user)

            super
          end

          def show
            @cart = find_cart
            promotion_switcher(@cart, true)

            super
          end

          def update_spl_card_activate # rubocop:disable Metrics/AbcSize
            find_cart!

            if params.dig('public_metadata', 'spl_card_active').nil?
              @cart.errors.add(:base, I18n.t('order.loyalty_card_missing'))
              render_errors(@cart.errors)
            else
              active_param = cast_boolean(params.dig('public_metadata', 'spl_card_active'))
              public_metadata = @cart.public_metadata
              update_spl_card_active_param(@cart, active_param, public_metadata)
              @cart.reload
              promotion_switcher(@cart, true)

              render_cart
            end
          end

          private

          def promotion_switcher(order, check_only)
            PromotionSwitcherService.new(order, check_only).call
          end

          def promotions_and_spl_adjustment_present?(order)
            order.promotions.any? && order.line_items.map { |li| li.adjustments.select { |a| a.preferred_external_source_type == 'SPL' } }.present?
          end

          def update_spl_card_active_param(order, active_param, public_metadata)
            order.update(public_metadata: public_metadata.merge('spl_card_active' => active_param))
            order.promotions.destroy_all if order.promotions.any?
          end

          def add_spl_discount_params_to_order(user)
            return if user&.public_metadata.blank?
            return unless user.public_metadata.key?('spl_no_card') && user.public_metadata.key?('spl_card_active')

            spl_card_active = cast_boolean(user.public_metadata['spl_card_active'])
            params[:public_metadata] ||= {}
            params[:public_metadata].merge!(spl_card_active: spl_card_active,
                                            spl_no_card: user.public_metadata['spl_no_card'])
          end

          def switch_spl_active_param(order, check_only)
            return if user&.public_metadata.blank?
            return unless order.public_metadata.key?('spl_card_active')

            if order.public_metadata[:spl_card_active] == true
              order.update(public_metadata: order.public_metadata.merge(spl_card_active: false))
            else
              order.update(public_metadata: order.public_metadata.merge(spl_card_active: true))
            end

            promotion_switcher(order, check_only)
          end

          def assign_spl_active_param(order, user)
            return if user&.public_metadata.blank?
            return unless user.public_metadata.key?(:spl_card_active)

            active_param = cast_boolean(user.public_metadata[:spl_card_active])
            spl_card = user.public_metadata[:spl_no_card]
            order.update(public_metadata: order.public_metadata.merge(spl_card_active: active_param,
                                                                      spl_no_card: spl_card))
          end

          def maintain_spl_adjustments(order)
            return unless order.public_metadata.key?(:spl_card_active)

            order.update(public_metadata: order.public_metadata.merge(spl_card_active: true))
            promotion_switcher(order, true)
          end
        end
      end
    end
  end
end
