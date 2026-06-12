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

        def connect_loyalty_account # rubocop:disable Metrics/AbcSize
          assign_card_number(try_spree_current_user, current_store, params)
          redirect_to safe_redirect_url(params[:redirect_to], spree.edit_account_profile_path),
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

        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockNesting
        def register_loyalty_account
          user = try_spree_current_user
          Spl::RegisterAccountService.new(user, current_store, params.dig('user', 'spl_auth_code')).call

          user.reload
          Rails.cache.delete("user_#{user.id}_spl_data")
          Rails.cache.delete("user_#{user.id}_spl_coupons")

          if user.private_metadata&.fetch('spl_access_token', nil).present?
            # Session upgrade succeeded — user has valid tokens
            redirect_to safe_redirect_url(params[:redirect_to], spree.edit_account_profile_path),
                        notice: ::Spree.t(:successfully_updated, resource: ::Spree.t(:account))
          else
            # Registration succeeded but session upgrade failed (no otpLoginToken or login failed).
            # Send a login OTP so the user can complete the connection.
            phone = PhoneParserService.new(user.phone)
            Spl::SendOtpService.new(DateTime.current, phone.country_code, phone.national_number, current_store).call
            user.errors.add(:base, I18n.t('spl.user.registration_success_enter_login_code'))
            # Render otp_code_form (posts to connect_loyalty_account) targeting
            # otp_registration_form (the element currently in the DOM).
            render turbo_stream: turbo_stream.replace(
              'otp_registration_form',
              partial: 'spl/otp_code_form',
              locals: { user: user, phone_e164: phone.e164 }
            ), status: :unprocessable_content
          end
        rescue Spl::RegisterAccountService::SplRegisterAccountError => e
          user = try_spree_current_user
          parsed_error = ::Spl::ErrorPayloadParser.parse(e.message) || {}

          if parsed_error.is_a?(Hash)
            error_code = parsed_error['errorCode']

            if %w[PERSON_MOBILE_ALREADY_EXISTS PERSON_EMAIL_ALREADY_EXISTS].include?(error_code)
              begin
                # Reuse the OTP the user already submitted to log in and assign their existing card
                Spl::LoginAccountService.new(user, current_store, params).call
                AssignSpartaCardNumberService.new(user, current_store).call

                user.reload
                Rails.cache.delete("user_#{user.id}_spl_data")
                Rails.cache.delete("user_#{user.id}_spl_coupons")

                redirect_to safe_redirect_url(params[:redirect_to], spree.edit_account_profile_path),
                            notice: ::Spree.t(:successfully_updated, resource: ::Spree.t(:account))
                return
              rescue StandardError => connect_error
                Rails.logger.error("[SPL] Auto-connect after PERSON_EXISTS failed: #{connect_error.class}: #{connect_error.message}")
                # Auto-connect failed (likely because the OTP was single-use).
                # Send a new SMS and show the login form as the translation promises.
                phone = PhoneParserService.new(user.phone)
                begin
                  Spl::SendOtpService.new(DateTime.current, phone.country_code, phone.national_number, current_store).call
                  error_key = error_code == 'PERSON_MOBILE_ALREADY_EXISTS' ? 'person_mobile_already_exists_sms' : 'person_email_already_exists_sms'
                  user.errors.add(:base, I18n.t("spl.errors.#{error_key}", email: user.email))
                rescue Spl::SendOtpService::SplSendOtpError => otp_error
                  handle_spl_error(otp_error, user)
                end

                render turbo_stream: turbo_stream.replace(
                  'otp_registration_form',
                  partial: 'spl/otp_code_form',
                  locals: { user: user, phone_e164: phone.e164 }
                ), status: :unprocessable_content
                return
              end
            end
          end

          handle_spl_error(e, user)
          render_connect_loyalty_account_error(user, user.phone, 'otp_registration_form')
        rescue Spl::OauthTokenService::OauthTokenError => e
          user = try_spree_current_user
          handle_spl_error(e, user)
          render_connect_loyalty_account_error(user, user.phone, 'otp_registration_form')
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockNesting

        private

        def validate_spl_no_card
          metadata = user_params[:public_metadata]
          return unless metadata&.[](:spl_no_card)

          update_order(metadata[:spl_no_card], metadata[:spl_card_active])
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

          ::Spl::ValidateCardService.new(metadata[:spl_no_card], try_spree_current_user, current_store).call
        end

        def handle_validation_error(error)
          flash[:error] = error.message
        end

        def update_order(spl_card, active)
          current_order = try_spree_current_user.orders.last
          return if current_order.nil?
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
          value = user_params.dig(:public_metadata, :spl_card_active)
          cast_boolean(value)
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
          cast_boolean(login_code_params[:accept_yc_terms])
        end

        def phone_parser
          @phone_parser ||= PhoneParserService.new(login_code_params[:phone])
        end

        def send_otp(phone, store)
          Spl::SendOtpService.new(DateTime.current, phone.country_code, phone.national_number, store).call
        end

        def update_user_after_otp_request
          try_spree_current_user.update(
            phone: login_code_params[:phone],
            public_metadata: (try_spree_current_user.public_metadata || {}).merge('accept_yc_terms' => true)
          )
        end

        def assign_card_number(user, store, params)
          Spl::LoginAccountService.new(user, store, params).call
          AssignSpartaCardNumberService.new(user, store).call
        end

        def login_code_params
          params.require(:user).permit(:phone, :accept_yc_terms)
        end

        def user_params
          params.require(:user).permit(:first_name, :last_name, :phone, :email,
                                       public_metadata: %i[spl_card_active spl_no_card])
        end

        def safe_redirect_url(redirect_param, default_path)
          return default_path if redirect_param.blank?

          uri = URI.parse(redirect_param)
          # Only allow relative URLs or same-host URLs
          return redirect_param if uri.relative? || uri.host == request.host

          default_path
        rescue URI::InvalidURIError
          default_path
        end
      end
    end
  end
end
