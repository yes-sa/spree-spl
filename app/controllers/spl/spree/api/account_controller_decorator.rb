# frozen_string_literal: true

module Spl
  module Spree
    module Api
      # Account decorator to validate spl card no
      module AccountControllerDecorator
        include ErrorHandlingHelper

        def self.prepended(base)
          base.before_action :validate_spl_no_card, only: :update
        end

        # The update service assigned the submitted card straight to the user;
        # it lives on metafields now, so it is written here instead - still
        # after the update, and still clearing whatever the submitted hash
        # left out.
        def update
          super

          sync_spl_metafields if response.successful?
        end

        def connect_loyalty_account
          spree_authorize! :update, spree_current_user
          assign_card_number(spree_current_user, current_store, params)
          spree_current_user.reload
          render_serialized_payload { serialize_resource(spree_current_user) }
        rescue Spl::LoginAccountService::SplLoginAccountError, AssignSpartaCardNumberService::AssignSpartaCardNumberError,
               Spl::MeService::SplMeError => e
          handle_spl_error(e, spree_current_user)
          render json: { error: spree_current_user.errors }, status: :bad_request
        end

        def register_loyalty_account
          spree_authorize! :update, spree_current_user
          Spl::RegisterAccountService.new(spree_current_user, current_store, params).call
          spree_current_user.reload
          render_serialized_payload { serialize_resource(spree_current_user) }
        rescue Spl::RegisterAccountService::SplRegisterAccountError, Spl::OauthTokenService::OauthTokenError => e
          handle_spl_error(e, spree_current_user)
          render json: { error: spree_current_user.errors }, status: :bad_request
        end

        def registration_code
          Spl::RequestOtpService.new(DateTime.current, current_store, params).call
          head :no_content
        rescue Spl::RequestOtpService::SplRequestOtpError, Spl::OauthTokenService::OauthTokenError => e
          handle_spl_error(e, spree_current_user)
          render json: { error: spree_current_user.errors }, status: :bad_request
        end

        def login_code
          spree_authorize! :update, spree_current_user
          Spl::SendOtpService.new(DateTime.current, params[:mobile_country], params[:phone_number], current_store).call
          head :no_content
        rescue Spl::SendOtpService::SplSendOtpError => e
          handle_spl_error(e, spree_current_user)
          render json: { error: spree_current_user.errors }, status: :bad_request
        end

        private

        # Read straight off `params`: `spl` is deliberately not among the
        # permitted user attributes, because the card is stored on metafields
        # rather than on the user record.
        def spl_card_params
          params[:user]&.[](:spl)
        end

        def assign_card_number(user, store, params)
          Spl::LoginAccountService.new(user, store, params).call
          AssignSpartaCardNumberService.new(user, store).call
        end

        def validate_spl_no_card
          return if spl_card_params.blank?
          return if disactivated_card?
          return if spl_card_params[:card_number].blank?

          Spl::ValidateCardService.new(spl_card_params[:card_number],
                                       spree_current_user,
                                       current_store).call
        rescue Spl::ValidateCardService::SplCardValidationError => e
          update_order
          render json: { error: e.message }, status: :bad_request
        end

        def update_order(spl_card: nil, active: false)
          current_order = spree_current_user.orders.last
          return unless %w[cart address delivery payment].include?(current_order.state)

          Spl::Metafields.set_card_number(current_order, spl_card)
          Spl::Metafields.set_card_active(current_order, active)
        end

        def sync_spl_metafields
          metadata = spl_card_params
          return if metadata.nil?

          Spl::Metafields.set_card_number(spree_current_user, metadata[:card_number])
          Spl::Metafields.set_card_active(spree_current_user, metadata[:card_active])
          Spl::Metafields.set_accept_terms(spree_current_user, metadata[:accept_terms])
        end

        def disactivated_card?
          !spl_card_params&.[](:card_active).nil? && !spl_card_params[:card_active]
        end
      end
    end
  end
end
