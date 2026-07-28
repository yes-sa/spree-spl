# frozen_string_literal: true

module Spl
  module Spree
    module Storefront
      module CheckoutControllerDecorator
        include ErrorHandlingHelper
        include BooleanHelper

        def self.prepended(base)
          base.before_action :promotion_switcher
          base.before_action :load_user_coupons, except: %i[activate_coupon deactivate_coupon]
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

        private

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

        def promotion_switcher
          PromotionSwitcherService.new(@order, checkout_state_allowed?).call
        end

        def checkout_state_allowed?
          %w[cart address delivery payment].include?(request.path.split('/').last)
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
