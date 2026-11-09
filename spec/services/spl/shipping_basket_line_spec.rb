# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spl::ShippingBasketLine do
  around do |example|
    previous_code = Spree::Spl.config.shipping_product_code
    previous_pos = Spree::Spl.config.shipping_basket_pos
    previous_resolver = Spree::Spl.config.shipping_amount_resolver
    example.run
  ensure
    Spree::Spl.config.shipping_product_code = previous_code
    Spree::Spl.config.shipping_basket_pos = previous_pos
    Spree::Spl.config.shipping_amount_resolver = previous_resolver
  end

  describe 'when shipping_product_code is not configured' do
    before { Spree::Spl.config.shipping_product_code = nil }

    it 'is disabled' do
      expect(described_class).not_to be_enabled
      expect(described_class.amount_for(create(:order))).to be_nil
    end
  end

  describe 'when shipping_product_code is configured' do
    before do
      Spree::Spl.config.shipping_product_code = 'HOST-SHIPPING-SKU'
      Spree::Spl.config.shipping_basket_pos = -1
    end

    it 'builds a basket row with the host-configured SKU' do
      expect(described_class.basket_item(19.99)).to eq(
        pos: -1,
        quantity: 1,
        productCode: 'HOST-SHIPPING-SKU',
        amountGross: 19.99,
        notPromoted: false
      )
    end

    it 'returns nil when the order has no shipments even if a resolver is set' do
      Spree::Spl.config.shipping_amount_resolver = ->(_order) { 12.5 }
      expect(described_class.amount_for(create(:order))).to be_nil
    end

    it 'uses configured resolver when the order has a shipment' do
      order = create(:order)
      create(:shipment, order: order, cost: 9.99)
      Spree::Spl.config.shipping_amount_resolver = ->(_order) { 12.5 }

      expect(described_class.amount_for(order.reload)).to eq(12.5)
    end

    it 'returns nil for zero-cost shipments so amountGross: 0 is never sent' do
      order = create(:order)
      create(:shipment, order: order, cost: 0)
      Spree::Spl.config.shipping_amount_resolver = ->(_order) { 0 }

      expect(described_class.amount_for(order.reload)).to be_nil
    end
  end
end
