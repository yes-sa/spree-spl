# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::Cart, type: :model do
  let(:klass) do
    Class.new do
      include Spree::Cart
      include CartDecorator

      attr_accessor :order
    end
  end

  let(:instance) { klass.new }
  let(:order) { create(:order) }
  let(:card_number) { nil }
  let(:card_active) { nil }

  before do
    Spl::Metafields.set_card_number(order, card_number)
    Spl::Metafields.set_card_active(order, card_active)
    instance.order = order
  end

  describe '#order_spl? (private)' do
    context 'when nothing is stored' do
      it 'returns false' do
        expect(instance.send(:order_spl?)).to be(false)
      end
    end

    context 'when the card number is missing' do
      let(:card_active) { true }

      it 'returns false' do
        expect(instance.send(:order_spl?)).to be(false)
      end
    end

    context 'when the card state is missing' do
      let(:card_number) { '0123456789123' }

      it 'returns false' do
        expect(instance.send(:order_spl?)).to be(false)
      end
    end

    context 'when both are stored and the card is active' do
      let(:card_number) { '0123456789123' }
      let(:card_active) { true }

      it 'returns the stored card state' do
        expect(instance.send(:order_spl?)).to be(true)
      end
    end

    context 'when the card is inactive' do
      let(:card_number) { '0123456789123' }
      let(:card_active) { false }

      it 'returns the stored card state' do
        expect(instance.send(:order_spl?)).to be(false)
      end
    end
  end
end
