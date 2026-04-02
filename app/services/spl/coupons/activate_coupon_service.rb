# frozen_string_literal: true

require 'json'

module Spl
  module Coupons
    class ActivateCouponService < BaseCouponService
      class ActivateCouponServiceError < StandardError; end

      def initialize(user, store, coupon_code)
        @store = store
        @activate_coupons_url = URI.parse(Spl::UrlCreatorService.new(store.private_metadata['spl_url']).coupon_activate)
        @user = user
        @coupon_code = coupon_code
        @retry_counter = 0
      end

      def call
        return unless satisfied_preconditions?(@user&.private_metadata)

        response = send_request(@activate_coupons_url, body)
        response_body = JSON.parse(response.body)
        Rails.logger.debug response_body
        raise ActivateCouponServiceError, response_body['msg'] if response_body['errorCode'] != '0'

        response_body['response']
      rescue ActivateCouponServiceError => e
        raise e unless token_refresh_needed(response_body, @retry_counter, @user, @store)

        @retry_counter += 1
        retry
      end

      private

      def body
        {
          context: {
            prgCode: @store.private_metadata['spl_prg_code'],
            oauthToken: @user.private_metadata['spl_access_token']
          },
          couponCode: @coupon_code
        }
      end
    end
  end
end
