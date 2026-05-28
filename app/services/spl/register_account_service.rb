# frozen_string_literal: true

require 'json'

module Spl
  class RegisterAccountService
    class SplRegisterAccountError < StandardError; end
    include SplServiceHelper

    def initialize(user, store, params)
      @register_url = URI.parse(Spl::UrlCreatorService.new(store.private_metadata['spl_url']).register)
      @user = user
      @store = store
      @params = params
      @phone = PhoneParserService.new(user.phone)
    end

    def call
      oauth_response_body = Spl::OauthTokenService.new(DateTime.current, @store).annonymus_token
      access_token = oauth_response_body.dig('response', 'accessToken')

      register_body = prepare_registration_body(access_token)
      register_response = send_request(@register_url, register_body)
      register_response_body = JSON.parse(register_response.body)
      Rails.logger.debug register_response_body
      raise SplRegisterAccountError, register_response_body if register_response_body['errorCode'] != '0'

      spl_card = register_response_body.dig('response', 'cardNo')
      update_account(spl_card, oauth_response_body)
      upgrade_session_if_needed(register_response_body, spl_card)
    end

    private

    def upgrade_session_if_needed(register_response_body, spl_card)
      return if (otp_token = register_response_body.dig('response', 'otpLoginToken')).blank?

      # Trigger an internal login to upgrade the session immediately
      Spl::LoginAccountService.new(
        @user,
        @store,
        { 'user' => { 'spl_auth_code' => otp_token, 'card_number' => spl_card } },
        raw_otp: true
      ).call
    end

    def prepare_registration_body(access_token) # rubocop:disable Metrics/MethodLength
      accept_yc_terms = @user.public_metadata['accept_yc_terms']
      {
        context: {
          oauthToken: access_token,
          prgCode: @store.private_metadata['spl_prg_code']
        },
        person: {
          firstName: @user[:first_name],
          lastName: @user[:last_name],
          email: @user[:email],
          mobileCountry: @phone.country_code,
          mobile: @phone.national_number,
          permissions: {
            processData: accept_yc_terms,
            operationalSms: accept_yc_terms
          }
        },
        authCode: @params,
        partnerCode: @store.private_metadata['spl_partner_code'],
        placeCode: @store.private_metadata['spl_place_code']
      }
    end

    def update_account(card_number, oauth_response_body)
      @user.private_metadata ||= {} if @user.private_metadata.blank?
      @user.update(public_metadata: @user.public_metadata.merge(spl_no_card: card_number, spl_card_active: true),
                   private_metadata: @user.private_metadata.merge(
                     spl_access_token: oauth_response_body.dig('response', 'accessToken'),
                     spl_refresh_token: oauth_response_body.dig('response', 'refreshToken')
                   ))
    end
  end
end
