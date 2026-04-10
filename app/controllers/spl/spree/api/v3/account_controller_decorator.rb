# frozen_string_literal: true

module Spl
  module Spree
    module Api
      module V3
        module AccountControllerDecorator
          include ErrorHandlingHelper

          def self.prepended(base)
            base.before_action :validate_spl_no_card, only: :update
          end

          def connect_loyalty_account
            authorize! :update, current_user
            assign_card_number(current_user, current_store, params)
            current_user.reload
            render json: serialize_resource(current_user)
          rescue Spl::LoginAccountService::SplLoginAccountError, AssignSpartaCardNumberService::AssignSpartaCardNumberError,
                 Spl::MeService::SplMeError => e
            handle_spl_error(e, current_user)
            render json: { error: current_user.errors }, status: :bad_request
          end

          def register_loyalty_account
            authorize! :update, current_user
            Spl::RegisterAccountService.new(current_user, current_store, params).call
            current_user.reload
            render json: serialize_resource(current_user)
          rescue Spl::RegisterAccountService::SplRegisterAccountError, Spl::OauthTokenService::OauthTokenError => e
            handle_spl_error(e, current_user)
            render json: { error: current_user.errors }, status: :bad_request
          end

          def registration_code
            Spl::RequestOtpService.new(DateTime.current, current_store, params).call
            head :no_content
          rescue Spl::RequestOtpService::SplRequestOtpError, Spl::OauthTokenService::OauthTokenError => e
            handle_spl_error(e, current_user)
            render json: { error: current_user.errors }, status: :bad_request
          end

          def login_code
            authorize! :update, current_user
            Spl::SendOtpService.new(DateTime.current, params[:mobile_country], params[:phone_number], current_store).call
            head :no_content
          rescue Spl::SendOtpService::SplSendOtpError => e
            handle_spl_error(e, current_user)
            render json: { error: current_user.errors }, status: :bad_request
          end

          private

          def assign_card_number(user, store, params)
            Spl::LoginAccountService.new(user, store, params).call
            AssignSpartaCardNumberService.new(user, store).call
          end

          def validate_spl_no_card
            return if permitted_params[:metadata].blank?
            return if disactivated_card?
            return if permitted_params.dig(:metadata, :spl_no_card).blank?

            Spl::ValidateCardService.new(permitted_params.dig(:metadata, :spl_no_card),
                                         current_user,
                                         current_store).call
          rescue Spl::ValidateCardService::SplCardValidationError => e
            update_order
            render json: { error: e.message }, status: :bad_request
          end

          def update_order(spl_card: nil, active: false)
            current_order = current_user.orders.last
            return unless %w[cart address delivery payment].include?(current_order.state)

            current_order.update(
              public_metadata: current_order.public_metadata.merge(
                {
                  'spl_no_card' => spl_card,
                  'spl_card_active' => active
                }
              )
            )
          end

          def disactivated_card?
            !permitted_params.dig(:metadata, :spl_card_active).nil? &&
              !permitted_params[:metadata][:spl_card_active]
          end
        end
      end
    end
  end
end
