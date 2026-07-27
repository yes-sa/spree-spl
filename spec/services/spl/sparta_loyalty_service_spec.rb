# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spl::SpartaLoyaltyService, type: :service do
  let(:country) { create(:country) }

  let(:store) do
    create(
      :store,
      default_country: country,
      private_metadata: {
        'spl_url' => 'https://spl.test',
        'spl_api_user' => 'user',
        'spl_api_token' => 'token',
        'spl_partner_code' => 'partner',
        'spl_place_code' => 'place',
        'spl_update_status_mode' => 'mode',
        'spl_prg_code' => 'PRG',
        'spl_mode' => 'mode',
        'spl_pos_key' => 'poskey'
      }
    )
  end

  let(:order_token) { 'ORDER123' }
  let(:card_number) { '5100179585157' }
  let(:date)        { DateTime.parse('2025-01-01 12:00:00') }
  let(:check_only)  { true }
  let(:product1) { create(:product) }
  let(:variant1) do
    create(
      :variant,
      product: product1,
      price: 6.75,
      compare_at_price: 6.75,
      sku: 'BS49252-BZ020-PSA000-000'
    )
  end

  let(:product2) { create(:product) }
  let(:variant2) do
    create(
      :variant,
      product: product2,
      price: 24.0,
      sku: 'BS49252-BZ020-PSA000-001'
    )
  end

  let(:line_item1) do
    create(
      :line_item,
      variant: variant1,
      quantity: 1,
      price: 6.75
    )
  end

  let(:line_item2) do
    create(
      :line_item,
      variant: variant2,
      quantity: 3,
      price: 24.0
    )
  end

  let(:line_items) { [line_item1, line_item2] }
  let(:products)   { [product1, product2] }

  let(:service) do
    described_class.new(
      order_token,
      card_number,
      line_items,
      date,
      products,
      check_only,
      store
    )
  end

  let(:url_creator_double) { instance_double(Spl::UrlCreatorService, sale: 'https://spl.test/sale') }
  let(:send_request_service_double) { instance_double(Spl::SendRequestService) }

  before do
    allow(Spl::UrlCreatorService).to receive(:new)
      .with(store.private_metadata['spl_url'])
      .and_return(url_creator_double)
  end

  describe '#call' do
    let(:http_response) { instance_double(Net::HTTPSuccess, body: response_body_hash.to_json) }

    let(:response_body_hash) do
      {
        'errorCode' => '0',
        'balanceBurn' => 0.0,
        'balanceEarn' => 0.0,
        'balanceAfter' => 0.12,
        'bookedEarn' => false,
        'processId' => '663c92b05012e0b396ac632b',
        'messages' => [],
        'basket' => [
          {
            'productCode' => 'BS49252-BZ020-PSA000-000',
            'productCode2' => nil,
            'quantity' => 1.0,
            'amountGross' => 6.75,
            'discountGross' => 0.0,
            'discountPercent' => nil,
            'unitPriceGross' => 6.75,
            'discounts' => nil,
            'isAward' => nil,
            'notPromoted' => nil,
            'skipCB' => nil,
            'skipDD' => nil,
            'skipRD' => nil,
            'pos' => 1
          },
          {
            'productCode' => 'BS49252-BZ020-PSA000-001',
            'productCode2' => nil,
            'quantity' => 3.0,
            'amountGross' => 23.2,
            'discountGross' => 0.8,
            'discountPercent' => nil,
            'unitPriceGross' => 7.73,
            'discounts' => [
              {
                'source' => 'LP',
                'amount' => 0.8,
                'percent' => 5.0,
                'code' => '663c926e5012e0b396ac6328',
                'name' => '5% discount for BS49252-BZ020-PSA000-001',
                'order' => 1,
                'quantity' => 2.0,
                'unitPriceGrossDiscounted' => nil
              }
            ],
            'isAward' => nil,
            'notPromoted' => nil,
            'skipCB' => nil,
            'skipDD' => nil,
            'skipRD' => nil,
            'pos' => 2
          }
        ],
        'basketChanged' => true,
        'amountGross' => 29.95,
        'discountGross' => 0.8,
        'coupons' => [],
        'cardType' => { 'code' => 'DV' },
        'requestId' => '00003_LSHRV'
      }
    end

    context 'when Sparta returns HTTP success and errorCode = "0"' do
      before do
        allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      end

      it 'sends Sparta-like payload and returns parsed response' do
        captured_body = nil

        expect(Spl::SendRequestService).to receive(:new) do |url, body|
          expect(url).to eq(URI.parse('https://spl.test/sale'))
          captured_body = body
          send_request_service_double
        end

        expect(send_request_service_double).to receive(:call).and_return(http_response)

        result = service.call
        expect(result).to eq(response_body_hash)

        expect(captured_body).to include(
          date: (date.to_i * 1000),
          no: order_token,
          orderNo: order_token,
          partnerCode: 'partner',
          pending: true,
          reverse: false,
          cardNo: '5100179585157',
          apiUser: 'user',
          mode: 'mode',
          apiToken: 'token',
          placeCode: 'place',
          checkOnly: check_only,
          ver: 4
        )

        # basket structure similar to Sparta template
        expect(captured_body[:basket]).to match(
          [
            {
              pos: line_item1.id,
              productCode: 'BS49252-BZ020-PSA000-000',
              quantity: 1,
              amountGross: 6.75,
              notPromoted: false
            },
            {
              pos: line_item2.id,
              productCode: 'BS49252-BZ020-PSA000-001',
              quantity: 3,
              amountGross: 7.73,
              notPromoted: false
            }
          ]
        )

        expect(captured_body[:ver]).to eq(4)
        expect(captured_body[:signature]).to be_a(String)
        expect(captured_body[:signature].size).to eq(64)
      end

      context 'when basket_amount_gross is :line_total' do
        before { Spree::Spl.config.basket_amount_gross = :line_total }
        after { Spree::Spl.config.basket_amount_gross = :unit_price }

        it 'uses line item amount for amountGross' do
          expect(Spl::SendRequestService).to receive(:new) do |_url, body|
            expect(body[:basket].pluck(:amountGross)).to eq(
              [line_item1.amount.to_f, line_item2.amount.to_f]
            )
            send_request_service_double
          end
          expect(send_request_service_double).to receive(:call).and_return(http_response)

          service.call
        end
      end
    end

    context 'when HTTP response is not success' do
      let(:http_response) { instance_double(Net::HTTPInternalServerError) }

      it 'returns nil' do
        expect(Spl::SendRequestService).to receive(:new).and_return(send_request_service_double)
        expect(send_request_service_double).to receive(:call).and_return(http_response)
        expect(service.call).to be_nil
      end
    end

    context 'when HTTP is success but errorCode is not "0"' do
      let(:response_body_hash) do
        {
          'errorCode' => '123',
          'message' => 'Some Sparta error'
        }
      end

      before do
        allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      end

      it 'raises SplSendRequestError with response body' do
        expect(Spl::SendRequestService).to receive(:new).and_return(send_request_service_double)
        expect(send_request_service_double).to receive(:call).and_return(http_response)

        expect do
          service.call
        end.to raise_error(
          Spl::SpartaLoyaltyService::SplSendRequestError,
          response_body_hash.to_s
        )
      end
    end
  end

  describe '#product_not_promoted?' do
    it 'returns true when compare_at_price is higher than price' do
      promo_variant = create(
        :variant,
        price: 10,
        compare_at_price: 20
      )
      promo_product = create(:product, variants: [promo_variant])

      service_with_products = described_class.new(
        order_token,
        card_number,
        line_items,
        date,
        [promo_product],
        check_only,
        store
      )

      expect(
        service_with_products.send(:product_not_promoted?, promo_variant.id)
      ).to be true
    end
  end

  describe '#generate_signature' do
    it 'generates deterministic SHA256-based signature' do
      sig1 = service.send(:generate_signature)
      sig2 = service.send(:generate_signature)

      expect(sig1).to eq(sig2)
      expect(sig1).to be_a(String)
      expect(sig1.size).to eq(64)
    end
  end
end
