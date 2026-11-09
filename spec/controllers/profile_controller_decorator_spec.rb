# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::Account::ProfileController, type: :controller do
  let(:state) { create(:state, country: create(:country_us), name: 'Gdansk', abbr: 'GDA') }
  let(:store) { create(:store) }
  let(:user) { create(:user) }
  let(:service_double) { instance_double(Spl::ValidateCardService, call: true) }

  let!(:order) { create(:order, user: user, state: 'cart') }

  before do
    allow(controller).to receive(:current_store).and_return(store)
    allow(controller).to receive(:spree_current_user).and_return(user)
    allow(Spl::ValidateCardService).to receive(:new).and_return(service_double)
  end

  describe 'validate_spl_no_card' do
    context 'when spl_no_card is missing' do
      it 'does NOT call the ValidateCardService' do
        put :update, params: { user: { spl: { card_number: '', card_active: false } } }

        expect(Spl::ValidateCardService).not_to receive(:new)
      end
    end

    context 'when spl_card_active is false (card deactivated)' do
      it 'does NOT call ValidateCardService' do
        put :update, params: { user: { spl: { card_number: '1234567890123', card_active: false } } }

        expect(Spl::ValidateCardService).not_to receive(:new)
      end
    end

    context 'when spl_no_card exists and card is active' do
      it 'calls ValidateCardService with correct parameters' do
        put :update, params: { user: { spl: { card_number: '1234567890123', card_active: true } } }

        expect(service_double).to have_received(:call)
      end
    end

    context 'when the submitted metadata leaves a key out' do
      before do
        Spl::Metafields.set_card_number(user, '1234567890123')
        Spl::Metafields.set_accept_terms(user, true)
      end

      it 'clears the keys the submitted hash does not carry' do
        put :update, params: { user: { spl: { card_active: false } } }

        expect(Spl::Metafields.card_number(user)).to be_nil
        expect(Spl::Metafields.card_active(user)).to be(false)
        expect(Spl::Metafields.accept_terms(user)).to be_nil
      end
    end

    context 'when no spl params are submitted' do
      before { Spl::Metafields.set_card_number(user, '1234567890123') }

      it 'leaves the stored card alone' do
        put :update, params: { user: { first_name: 'Tamara' } }

        expect(Spl::Metafields.card_number(user)).to eq('1234567890123')
      end
    end

    context 'when spl_no_card exists and the order is still open' do
      it 'stamps the order with the submitted card' do
        put :update, params: { user: { spl: { card_number: '1234567890123', card_active: true } } }

        expect(Spl::Metafields.card_number(order)).to eq('1234567890123')
        expect(Spl::Metafields.card_active(order)).to be(true)
      end
    end

    context 'when the user update itself fails' do
      before { Spl::Metafields.set_card_number(user, '1111111111111') }

      it 'does not write the submitted card' do
        put :update, params: { user: { email: '', spl: { card_number: '1234567890123', card_active: true } } }

        expect(user.errors).not_to be_empty
        expect(Spl::Metafields.card_number(user)).to eq('1111111111111')
      end
    end

    context 'when ValidateCardService raises SplCardValidationError' do
      before do
        create(:order, user: user, state: 'cart')
        allow(service_double).to receive(:call).and_raise(Spl::ValidateCardService::SplCardValidationError.new('Invalid'))
      end

      it 'sets flash error message' do
        put :update, params: { user: { spl: { card_number: '1234567890123', card_active: 'true' } } }

        expect(flash[:error]).to eq('Invalid')
      end
    end
  end
end
