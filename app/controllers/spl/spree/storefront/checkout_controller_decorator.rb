# frozen_string_literal: true

module Spl
  module Spree
    module Storefront
      module CheckoutControllerDecorator # rubocop:disable Metrics/ModuleLength
        include ErrorHandlingHelper
        include BooleanHelper

        DISCOUNT_CODE_ACTIONS = %i[apply_discount_code remove_discount_code].freeze
        LOYALTY_COUPON_ACTIONS = %i[activate_coupon deactivate_coupon].freeze

        def self.prepended(base)
          # Typed discount-code actions always recalculate themselves.
          # When reprice_on_coupon_change is on, VC activate/deactivate also reprice after
          # the CWP call — skip the before_action sale. That before_action uses
          # checkOnly=false (path ends with activate_coupon), which can lock a pending
          # SPL tx without the newly activated coupon and wipe discounts.
          base.before_action :promotion_switcher, unless: :skip_promotion_switcher?
          base.before_action :load_user_coupons, except: (LOYALTY_COUPON_ACTIONS + DISCOUNT_CODE_ACTIONS)
          base.after_action :perform_update_sparta_state_job, only: %i[confirm complete]
        end

        def activate_coupon
          if ::Spree::Spl.config.reprice_on_coupon_change
            activate_coupon_with_reprice
          else
            activate_coupon_legacy
          end
        end

        def deactivate_coupon
          if ::Spree::Spl.config.reprice_on_coupon_change
            deactivate_coupon_with_reprice
          else
            deactivate_coupon_legacy
          end
        end

        def apply_discount_code
          return head :not_found unless ::Spree::Spl.config.manual_discount_codes?

          @discount_code_result = ::Spl::ManualCoupons::ApplyService.new(
            @order,
            params[:discount_code].presence || params[:coupon_code],
            user: @order.user,
            store: current_store
          ).call
          load_cart_line_items_for_discount_response
        ensure
          respond_to_discount_code_change if ::Spree::Spl.config.manual_discount_codes?
        end

        def remove_discount_code
          return head :not_found unless ::Spree::Spl.config.manual_discount_codes?

          @discount_code_result = ::Spl::ManualCoupons::RemoveService.new(
            @order,
            params[:discount_code].presence || params[:coupon_code],
            user: @order.user,
            store: current_store
          ).call
          load_cart_line_items_for_discount_response
        ensure
          respond_to_discount_code_change if ::Spree::Spl.config.manual_discount_codes?
        end

        private

        def load_cart_line_items_for_discount_response
          # Host apps may override to eager-load line items for turbo streams.
        end

        def respond_to_discount_code_change
          respond_to do |format|
            format.turbo_stream
            format.html { redirect_to checkout_path }
          end
        end

        def activate_coupon_legacy
          ::Spl::Coupons::ActivateCouponService.new(@order.user, @order.store, params[:coupon_code]).call
          load_user_coupons
        rescue StandardError => e
          handle_spl_error(e, @order.user)
          raise e
        ensure
          respond_to do |format|
            format.turbo_stream
            format.html { redirect_to checkout_path }
          end
        end

        def deactivate_coupon_legacy
          ::Spl::Coupons::DeactivateCouponService.new(@order.user, @order.store, params[:coupon_code]).call
          load_user_coupons
        rescue StandardError => e
          handle_spl_error(e, @order.user)
          raise e
        ensure
          respond_to do |format|
            format.turbo_stream
            format.html { redirect_to checkout_path }
          end
        end

        def activate_coupon_with_reprice
          clear_errors(@order.user)
          ::Spl::Coupons::ActivateCouponService.new(@order.user, @order.store, params[:coupon_code]).call
          recalculate_after_coupon_change!
          load_user_coupons
        rescue StandardError => e
          handle_spl_coupon_error(e)
        ensure
          respond_to_coupon_change
        end

        def deactivate_coupon_with_reprice
          clear_errors(@order.user)
          ::Spl::Coupons::DeactivateCouponService.new(@order.user, @order.store, params[:coupon_code]).call
          recalculate_after_coupon_change!
          load_user_coupons
        rescue StandardError => e
          handle_spl_coupon_error(e)
        ensure
          respond_to_coupon_change
        end

        def recalculate_after_coupon_change!
          @order.reload
          RemoveSpartaDiscountService.destroy_all_sparta_adjustments(@order)
          ::Spl::RecalculateOrderService.bump_coupon_version!(@order)
          ::Spl::RecalculateOrderService.new(
            @order.reload,
            user: @order.user,
            store: current_store,
            force: true
          ).call
        end

        def handle_spl_coupon_error(error)
          handle_spl_error(error, @order.user)
          raise error unless suppress_coupon_error_raise?
        end

        def suppress_coupon_error_raise?
          false
        end

        def respond_to_coupon_change
          respond_to do |format|
            format.turbo_stream
            format.html { redirect_to checkout_path }
          end
        end

        def skip_promotion_switcher?
          action = action_name.to_sym
          return true if action == :complete
          return true if DISCOUNT_CODE_ACTIONS.include?(action)
          return true if LOYALTY_COUPON_ACTIONS.include?(action) && ::Spree::Spl.config.reprice_on_coupon_change

          false
        end

        def promotion_switcher
          PromotionSwitcherService.new(@order, checkout_state_allowed?).call
        end

        def checkout_state_allowed?
          !final_confirm_submission?
        end

        def final_confirm_submission?
          action_name == 'update' && params[:state].to_s == 'confirm' && @order&.confirm?
        end

        def perform_update_sparta_state_job
          if @order.payment_state == 'paid'
            UpdateSpartaStateJob.perform_later(@order.token, 'D', @order.number, @order.store)
          end
          if @order.state == 'canceled'
            UpdateSpartaStateJob.perform_later(@order.token, 'C', @order.number, @order.store)
          end
        end

        def load_user_coupons
          @coupons = ::Spl::Coupons::GetCouponsService.new(@order.user, @order.store).call
        rescue StandardError => e
          handle_spl_error(e, @order.user)
          raise e
        end
      end
    end
  end
end
