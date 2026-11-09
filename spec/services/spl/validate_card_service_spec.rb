# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spl::ValidateCardService do
  subject(:service) { described_class.new(card_number, user, store) }

  let(:country) { create(:country) }
  let(:store) { create(:store, default_country: country) }
  let(:user) { create(:user) }
  let(:card_number) { '1234567890123' }

  before do
    Spl::Metafields.set_card_number(user, '1234567890123')
    Spl::Metafields.set_card_active(user, true)
    allow(service).to receive(:verify_card_request).and_return(
      { errorCode: '0', response: { card: { status: 'A' } } }.to_json
    )
    allow(service).to receive(:cards_assigned_user).and_return(nil)
  end

  describe '#call' do
    it 'restores the card state once validation passes' do
      service.call

      expect(Spl::Metafields.card_active(user)).to be(true)
    end

    context 'when the card state was never set' do
      before { Spl::Metafields.set_card_active(user, nil) }

      it 'activates the card after successful validation' do
        service.call

        expect(Spl::Metafields.card_active(user)).to be(true)
      end
    end

    context 'when API returns error' do
      before do
        allow(service).to receive(:verify_card_request).and_return({ errorCode: '1', msg: 'Invalid card' }.to_json)
      end

      it 'leaves the card deactivated' do
        expect { service.call }.to raise_error(Spl::ValidateCardService::SplCardValidationError)

        expect(Spl::Metafields.card_active(user)).to be(false)
      end
    end

    context "when card status is not 'A'" do
      before do
        allow(service).to receive(:verify_card_request).and_return(
          { errorCode: '0', response: { card: { status: 'B' } } }.to_json
        )
      end

      it 'raises SplCardValidationError and leaves the card deactivated' do
        expect do
          service.call
        end.to raise_error(
          Spl::ValidateCardService::SplCardValidationError,
          I18n.t('spl.card_validation.errors.card_not_active')
        )

        expect(Spl::Metafields.card_active(user)).to be(false)
      end
    end

    context 'when an unexpected error occurs' do
      before { allow(service).to receive(:verify_card_request).and_raise(StandardError, 'boom') }

      it 'persists the deactivated card' do
        expect { service.call }.to raise_error(StandardError)

        expect(Spl::Metafields.card_active(user)).to be(false)
      end
    end
  end
end
