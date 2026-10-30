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
    end

    private

    def prepare_registration_body(access_token) # rubocop:disable Metrics/MethodLength
      accept_yc_terms = ::Spl::Metafields.accept_terms(@user)
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
      @user.update(private_metadata: @user.private_metadata.merge(
        spl_access_token: oauth_response_body.dig('response', 'accessToken'),
        spl_refresh_token: oauth_response_body.dig('response', 'refreshToken')
      ))

      ::Spl::Metafields.set_card_number(@user, card_number)
      ::Spl::Metafields.set_card_active(@user, true)
    end
  end
end
