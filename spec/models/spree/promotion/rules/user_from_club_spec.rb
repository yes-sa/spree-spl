# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::Promotion::Rules::UserFromClub, type: :model do
  let(:state) { create(:state, country: create(:country_us), name: 'Gdansk', abbr: 'GDA') }
  let(:store) { create(:store) }
  let(:user) { create(:user) }
  let(:card_active) { true }
  let(:order) { create(:order_with_totals, store: store, user: user) }
  let(:rule) { described_class.new }

  before do
    Spl::Metafields.set_card_number(user, '1234567890123')
    Spl::Metafields.set_card_active(user, card_active)
  end

  describe '#applicable?' do
    it 'returns true for Spree::Order' do
      expect(rule.applicable?(order)).to be true
    end

    it 'returns false for non-order promotable' do
      product = build_stubbed(:product)
      expect(rule.applicable?(product)).to be false
    end
  end

  describe '#eligible?' do
    let(:service_double) { instance_double(Spl::ValidateCardService, call: true) }

    before do
      allow(Spl::ValidateCardService).to receive(:new)
        .with('1234567890123', user, store)
        .and_return(service_double)
    end

    context 'when card is active and valid' do
      it 'returns true' do
        expect(rule.eligible?(order)).to be true
      end

      it 'does not add any errors' do
        rule.eligible?(order)
        expect(rule.eligibility_errors).to be_empty
      end
    end

    context 'when card is inactive' do
      let(:card_active) { false }

      it 'returns false' do
        expect(rule.eligible?(order)).to be false
      end

      it 'adds error message' do
        rule.eligible?(order)
        expect(rule.eligibility_errors[:base]).not_to be_empty
      end
    end

    context 'when card validation fails' do
      before { allow(service_double).to receive(:call).and_return(false) }

      it 'returns false' do
        expect(rule.eligible?(order)).to be false
      end

      it 'adds error message' do
        rule.eligible?(order)
        expect(rule.eligibility_errors[:base]).not_to be_empty
      end
    end
  end
end
