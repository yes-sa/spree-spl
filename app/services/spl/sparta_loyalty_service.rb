# frozen_string_literal: true

require 'digest'
require 'net/http'
require 'json'

module Spl
  class SpartaLoyaltyService
    class SplSendRequestError < StandardError; end
    include SplServiceHelper

    def initialize(order_token, card_number, line_items, date, products, check_only, store, # rubocop:disable Metrics/ParameterLists
                   coupons: [], shipping_amount: nil)
      @order_token = order_token
      @card_number = card_number
      @line_items = line_items
      @date = date.to_i * 1000
      @products = products
      @check_only = check_only
      @store = store
      @coupons = Array(coupons).map { |code| code.to_s.strip }.compact_blank
      @shipping_amount = shipping_amount
      @url = URI.parse(Spl::UrlCreatorService.new(store.private_metadata['spl_url']).sale)
    end

    def call
      Rails.logger.debug 'SPL LOYALTY SERVICE START'
      basket_body = prepare_basket_body
      response = send_request(@url, basket_body)
      return unless response.is_a?(Net::HTTPSuccess)

      response_body = JSON.parse(response.body)
      Rails.logger.debug 'SPL LOYALTY SERVICE RESPONSE'
      Rails.logger.debug response.body.inspect
      raise SplSendRequestError, response_body unless response_body.present? && response_body['errorCode'] == '0'

      response_body
    end

    private

    def prepare_basket_body # rubocop:disable Metrics/MethodLength
      body = {
        ver: 4,
        apiUser: @store.private_metadata['spl_api_user'],
        apiToken: @store.private_metadata['spl_api_token'],
        partnerCode: @store.private_metadata['spl_partner_code'],
        placeCode: @store.private_metadata['spl_place_code'],
        mode: @store.private_metadata['spl_mode'],
        date: @date,
        no: @order_token,
        orderNo: @order_token,
        reverse: false,
        pending: true,
        checkOnly: @check_only,
        cardNo: @card_number,
        basket: prepare_basket,
        signature: generate_signature
      }
      body[:coupons] = @coupons if @coupons.any?
      body
    end

    def prepare_basket
      items = @line_items.map do |item|
        {
          pos: item.id,
          quantity: item.quantity,
          productCode: item.sku,
          amountGross: amount_gross_for(item),
          notPromoted: product_not_promoted?(item['variant_id'])
        }
      end
      return items if @shipping_amount.nil? || !@shipping_amount.to_d.positive?

      items + [ShippingBasketLine.basket_item(@shipping_amount)]
    end

    def amount_gross_for(item)
      case ::Spree::Spl.config.basket_amount_gross
      when :line_total
        item.amount.to_f
      else
        item.price.to_f
      end
    end

    def product_not_promoted?(variant_id)
      @products.any? do |product|
        (product.variants.presence || [product.default_variant]).any? do |var|
          var.id == variant_id && var.price != var.compare_at_price && var.compare_at_price.to_i.positive?
        end
      end
    end

    def generate_signature
      check_only = @check_only ? 1 : ''
      data = "#{@store.private_metadata['spl_partner_code']}#{@store.private_metadata['spl_place_code']}#{@date}#{@order_token}#{check_only}#{@card_number}" # rubocop:disable Layout/LineLength
      Rails.logger.debug data.inspect
      signature_base = Digest::SHA256.hexdigest(data)
      Digest::SHA256.hexdigest(signature_base + @store.private_metadata['spl_pos_key'])
    end
  end
end
