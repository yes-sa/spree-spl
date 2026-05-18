# frozen_string_literal: true

require 'json'

module Spl
  class LoginAccountService
    class SplLoginAccountError < StandardError; end
    include SplServiceHelper

    def initialize(user, store, params, raw_otp: false)
      @login_url = URI.parse(Spl::UrlCreatorService.new(store.private_metadata['spl_url']).login)
      @user = user
      @store = store
      @phone_number = user.phone
      @card_number = params.dig('user', 'card_number')
      @otp_code = params.dig('user', 'spl_auth_code')
      @env = Spl::StorePrivateMetadataService.all(store)
      @raw_otp = raw_otp
    end

    def call
      body = prepare_login_body
      response = send_request(@login_url, body)
      response_body = JSON.parse(response.body)
      Rails.logger.debug response_body
      raise SplLoginAccountError, response_body if response_body['errorCode'] != '0'

      access_token = response_body.dig('response', 'oauthCode')
      get_access_token(access_token)
    end

    private

    def prepare_login_body
      {
        context: {
          prgCode: @env['spl_prg_code']
        },
        apiUser: @env['spl_api_user'],
        scope: ['spl_cwp'],
        responseType: 'code',
        login: generate_login,
        password: encrypted_otp,
        method: 'OTP'
      }
    end

    def encrypted_otp
      return @otp_code if @raw_otp

      @otp_code.length == 6 ? Digest::SHA256.hexdigest(@otp_code) : @otp_code
    end

    def generate_login
      @card_number.presence || @phone_number.presence
    end

    def get_access_token(access_token)
      token_body = Spl::OauthTokenService.new(DateTime.current, @store).authorization_code_token(access_token)
      add_loyalty_tokens_to_user(token_body['accessToken'], token_body['refreshToken'])
    end

    def add_loyalty_tokens_to_user(access_token, refresh_token)
      @user.private_metadata ||= {} if @user.private_metadata.blank?
      @user.update!(private_metadata: @user.private_metadata.merge(
                      spl_access_token: access_token,
                      spl_refresh_token: refresh_token
                    ))
    end
  end
end
