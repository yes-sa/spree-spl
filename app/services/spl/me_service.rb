# frozen_string_literal: true

require 'json'

module Spl
  class MeService
    class SplMeError < StandardError; end
    include SplServiceHelper
    include ErrorHandlingHelper
    include LoginCheckHelper

    def initialize(user, store)
      @me_url = URI.parse(Spl::UrlCreatorService.new(store.private_metadata['spl_url']).me)
      @user = user
      @store = store
      @env = Spl::StorePrivateMetadataService.all(store)
      @retry_counter = 0
    end

    def call
      return unless @user.present? && @user.private_metadata.present?
      return unless logged_user?(@user)

      response = send_request(@me_url, body)
      response_body = JSON.parse(response.body)
      Rails.logger.debug response_body
      raise SplMeError, response_body if response_body['errorCode'] != '0'

      response_body
    rescue SplMeError => e
      raise e unless token_refresh_needed(response_body, @retry_counter, @user, @store)

      @retry_counter += 1
      retry
    end

    private

    def body
      {
        context: {
          prgCode: @env['spl_prg_code'],
          oauthToken: @user.private_metadata['spl_access_token']
        }
      }
    end
  end
end
