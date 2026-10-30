# frozen_string_literal: true

module Spl
  module Spree
    module Storefront
      module ProfileControllerDecorator # rubocop:disable Metrics/ModuleLength
        include BooleanHelper
        include ProfileControllerHelper
        include ErrorHandlingHelper

        def self.prepended(base)
          base.before_action :validate_spl_no_card, only: :update
          base.before_action :validate_login_code_request, only: %i[login_code registration_code]
        end

        def login_code
          send_otp(phone_parser, current_store)
          update_user_after_otp_request
          render_login_code_success(try_spree_current_user, phone_parser, 'otp_code_form')
        rescue Spl::SendOtpService::SplSendOtpError => e
          handle_spl_error(e, try_spree_current_user)
          render_login_code_error(try_spree_current_user)
        end

        def connect_loyalty_account
          assign_card_number(try_spree_current_user, current_store, params)
          redirect_to spree.edit_account_profile_path,
                      notice: ::Spree.t(:successfully_updated, resource: ::Spree.t(:account))
        rescue Spl::LoginAccountService::SplLoginAccountError, AssignSpartaCardNumberService::AssignSpartaCardNumberError,
               Spl::MeService::SplMeError => e
          handle_spl_error(e, try_spree_current_user)
          render_connect_loyalty_account_error(try_spree_current_user, try_spree_current_user.phone, 'otp_code_form')
        end

        def registration_code
          request_otp(phone_parser, current_store, params['user'])
          update_user_after_otp_request
          render_login_code_success(try_spree_current_user, phone_parser, 'otp_registration_form')
        rescue Spl::RequestOtpService::SplRequestOtpError, Spl::OauthTokenService::OauthTokenError => e
          handle_spl_error(e, try_spree_current_user)
          render_login_code_error(try_spree_current_user)
        end

        def register_loyalty_account
          Spl::RegisterAccountService.new(try_spree_current_user, current_store, params['user']['spl_auth_code']).call
          redirect_to spree.edit_account_profile_path,
                      notice: ::Spree.t(:successfully_updated, resource: ::Spree.t(:account))
        rescue Spl::RegisterAccountService::SplRegisterAccountError, Spl::OauthTokenService::OauthTokenError => e
          handle_spl_error(e, try_spree_current_user)
          user = try_spree_current_user
          render_connect_loyalty_account_error(user, user.phone, 'otp_registration_form')
        end

        # The action used to assign the submitted card straight to the user;
        # it lives on metafields now, so it is written here instead - still
        # after the update, and still clearing whatever the submitted hash
        # left out, exactly as assigning the whole column did.
        def update
          super

          sync_spl_metafields if try_spree_current_user.errors.empty?
        end

        private

        # Read straight off `params`: `spl` is deliberately not among the
        # permitted user attributes, because the card is stored on metafields
        # rather than on the user record.
        def spl_card_params
          params[:user]&.[](:spl)
        end

        def validate_spl_no_card
          metadata = spl_card_params
          return unless metadata&.[](:card_number)

          update_order(metadata[:card_number], metadata[:card_active])
          validate_card(metadata)
        rescue ::Spl::ValidateCardService::SplCardValidationError => e
          handle_validation_error(e)
        end

        def validate_login_code_request
          clear_errors(try_spree_current_user)
          validate_yc_terms
          validate_phone

          render_login_code_error(try_spree_current_user) if try_spree_current_user.errors.any?
        end

        def request_otp(phone, store, params)
          params.merge!(mobile_country: phone.country_code, phone_number: phone.national_number)
          Spl::RequestOtpService.new(DateTime.current, store, params).call
        end

        def validate_card(metadata)
          return unless disactivated_card?

          ::Spl::ValidateCardService.new(metadata[:card_number], try_spree_current_user, current_store).call
        end

        def handle_validation_error(error)
          flash[:error] = error.message
        end

        def update_order(spl_card, active)
          current_order = try_spree_current_user.orders.last
          return if current_order.nil?
          return unless %w[cart address delivery payment].include?(current_order.state)

          ::Spl::Metafields.set_card_number(current_order, spl_card)
          ::Spl::Metafields.set_card_active(current_order, active)
        end

        def sync_spl_metafields
          metadata = spl_card_params
          return if metadata.nil?

          ::Spl::Metafields.set_card_number(try_spree_current_user, metadata[:card_number])
          ::Spl::Metafields.set_card_active(try_spree_current_user, metadata[:card_active])
          # The terms consent was never part of what a profile update submits,
          # so assigning the whole column always dropped it. Reproduced on
          # purpose - delete this line if the consent should survive.
          ::Spl::Metafields.set_accept_terms(try_spree_current_user, nil)
        end

        def disactivated_card?
          cast_boolean(spl_card_params&.[](:card_active))
        end

        def validate_yc_terms
          return if yc_terms_accepted?

          try_spree_current_user.errors.add(:base, I18n.t('spl.user.errors.must_accept_yc_terms'))
        end

        def validate_phone
          return if phone_parser.valid?

          try_spree_current_user.errors.add(:phone, I18n.t('spl.user.errors.invalid_phone'))
        end

        def yc_terms_accepted?
          cast_boolean(login_code_params[:accept_spl_terms])
        end

        def phone_parser
          @phone_parser ||= PhoneParserService.new(login_code_params[:phone])
        end

        def send_otp(phone, store)
          Spl::SendOtpService.new(DateTime.current, phone.country_code, phone.national_number, store).call
        end

        def update_user_after_otp_request
          try_spree_current_user.update(phone: login_code_params[:phone])
          ::Spl::Metafields.set_accept_terms(try_spree_current_user, true)
        end

        def assign_card_number(user, store, params)
          Spl::LoginAccountService.new(user, store, params).call
          AssignSpartaCardNumberService.new(user, store).call
        end

        def login_code_params
          params.require(:user).permit(:phone, :accept_spl_terms)
        end

        def user_params
          params.require(:user).permit(:first_name, :last_name, :phone, :email)
        end
      end
    end
  end
end
