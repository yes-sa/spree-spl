# frozen_string_literal: true

require 'digest'
require 'net/http'
require 'json'

class UpdateSpartaStateJob < ActiveJob::Base # rubocop:disable Metrics/ClassLength
  ORDER_STATES = %w[C D].freeze
  ERROR_CODES = %w[ORDER_NOT_FOUND REQUEST_ALREADY_PROCESSED].freeze

  def perform(order_token, state, order_number, store) # rubocop:disable Metrics/MethodLength
    return if order_token.blank? || !ORDER_STATES.include?(state&.upcase)

    transaction = find_transaction(order_token, store)
    return if transaction.blank?

    Rails.logger.debug transaction.inspect

    date = DateTime.parse(transaction['date'])
    card_number = transaction['cardNo']
    basket = transaction['basket']
    coupons = transaction['coupons']

    case state
    when 'D'
      update_order_status(order_token, basket, date, card_number, store, order_number, coupons)
    when 'C'
      refund(order_token, basket, date, store, card_number)
    end
  end

  private

  def send_request(url, body) # rubocop:disable Metrics/AbcSize
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(url)
    request['Content-Type'] = 'application/json'
    request.body = body.to_json
    Rails.logger.debug request.body

    response = http.request(request)
    JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)
  end

  def update_order_status(order_token, basket, date, card_number, store, order_number = '', coupons = [])
    body = build_body(order_token, basket, date, card_number, order_number, store, coupons)
    sale_url = URI.parse(Spl::UrlCreatorService.new(store.private_metadata['spl_url']).sale)
    response_body = send_request(sale_url, body)
    handle_response(response_body)
  end

  def find_transaction(order_token, store)
    body = build_find_transaction_body(order_token, store)
    order_find_url = URI.parse(Spl::UrlCreatorService.new(store.private_metadata['spl_url']).find)
    response_body = send_request(order_find_url, body)
    response_body&.dig('response', 0) if response_body && response_body['errorCode'] == '0'
  end

  def refund(order_token, basket, date, store, card_number)
    body = build_refund_body(order_token, basket, date, card_number, store)
    refund_url = URI.parse(Spl::UrlCreatorService.new(store.private_metadata['spl_url']).sale_refund)
    response_body = send_request(refund_url, body)
    handle_response(response_body)
  end

  def build_body(order_token, basket, date, card_number, order_number, store, coupons) # rubocop:disable Metrics/MethodLength
    date_in_ms = date.to_i * 1000
    {
      ver: 4,
      apiUser: store.private_metadata['spl_api_user'],
      apiToken: store.private_metadata['spl_api_token'],
      partnerCode: store.private_metadata['spl_partner_code'],
      placeCode: store.private_metadata['spl_place_code'],
      mode: store.private_metadata['spl_update_status_mode'],
      pending: false,
      date: date_in_ms,
      no: order_token,
      cardNo: card_number,
      documentNo: order_number,
      basket: basket,
      coupons: coupon_codes(coupons),
      signature: generate_signature(order_token, store, date_in_ms, card_number, order_number)
    }
  end

  def build_find_transaction_body(order_token, store) # rubocop:disable Metrics/MethodLength
    date_in_ms = DateTime.current.to_i * 1000
    {
      ver: 3,
      apiUser: store.private_metadata['spl_api_user'],
      apiToken: store.private_metadata['spl_api_token'],
      partnerCode: store.private_metadata['spl_partner_code'],
      placeCode: store.private_metadata['spl_place_code'],
      requestDate: date_in_ms,
      no: order_token,
      prgCode: store.private_metadata['spl_prg_code'],
      orderNo: order_token,
      signature: generate_signature('', store, date_in_ms)
    }
  end

  def build_refund_body(order_token, basket, date, card_number, store) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
    date_in_ms = date.to_i * 1000
    new_number = SecureRandom.uuid
    {
      ver: 4,
      prgCode: store.private_metadata['spl_prg_code'],
      apiUser: store.private_metadata['spl_api_user'],
      apiToken: store.private_metadata['spl_api_token'],
      mode: store.private_metadata['spl_refund_mode'],
      partnerCode: store.private_metadata['spl_partner_code'],
      placeCode: store.private_metadata['spl_place_code'],
      relPartnerCode: store.private_metadata['spl_partner_code'],
      relPlaceCode: store.private_metadata['spl_place_code'],
      relDate: date_in_ms,
      relNo: order_token,
      date: date_in_ms,
      orderNo: new_number,
      no: new_number,
      cardNo: card_number,
      basket: basket,
      signature: generate_signature(new_number, store, date_in_ms, card_number)
    }
  end

  def generate_signature(order_number, store, date = '', card_number = '', check_only = '', order_name = '') # rubocop:disable Metrics/ParameterLists
    data = "#{store.private_metadata['spl_partner_code']}#{store.private_metadata['spl_place_code']}#{date}#{order_number}#{order_name}#{check_only}#{card_number}" # rubocop:disable Layout/LineLength
    Rails.logger.debug data.inspect
    signature_base = Digest::SHA256.hexdigest(data)
    Digest::SHA256.hexdigest(signature_base + store.private_metadata['spl_pos_key'])
  end

  def handle_response(response_body)
    return if response_body.present? && ERROR_CODES.include?(response_body['errorCode'])
    raise StandardError, response_body.inspect unless response_body.present? && response_body['errorCode'] == '0'

    Rails.logger.debug response_body.inspect
  end

  def coupon_codes(coupons)
    Array(coupons).filter_map do |coupon|
      if coupon.is_a?(Hash)
        coupon['code'] || coupon[:code]
      else
        coupon
      end
    end
  end
end
