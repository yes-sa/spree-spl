# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::Api::V3::Store::CartsController, type: :controller do
  let(:store) { Spree::Store.default || create(:store, default: true) }
  let(:user)  { create(:user, public_metadata: user_metadata) }
  let(:order) { create(:order, user: user, store: store, public_metadata: {}) }

  let(:user_metadata) { {} }

  before do
    allow(controller).to receive(:current_store).and_return(store)
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:find_cart).and_return(order)
    allow(controller).to receive(:find_cart!).and_return(order)
    allow(controller).to receive(:authenticate_user).and_return(true)
    allow(controller).to receive(:authenticate_api_key!).and_return(true)
    controller.instance_variable_set(:@cart, order)
    allow(PromotionSwitcherService).to receive_message_chain(:new, :call)
  end

  describe 'POST #create' do
    context 'when user has SPL metadata' do
      let(:user_metadata) do
        {
          'spl_no_card' => '0123456789123',
          'spl_card_active' => true
        }
      end

      it 'injects SPL params into request public_metadata' do
        post :create, params: { public_metadata: {} }, as: :json

        expect(controller.params[:public_metadata].permit!.to_h).to include(
          'spl_no_card' => '0123456789123',
          'spl_card_active' => true
        )
      end
    end

    context 'when user has no SPL metadata' do
      it 'does not modify params' do
        post :create, params: { public_metadata: {} }, as: :json

        expect(controller.params[:public_metadata].permit!.to_h).to eq({})
      end
    end
  end

  describe 'GET #show' do
    it 'runs PromotionSwitcherService in check-only mode' do
      expect(PromotionSwitcherService)
        .to receive(:new).with(order, true)
                         .and_call_original

      get :show, as: :json
    end
  end

  describe 'PATCH #update_spl_card_activate' do
    context 'when spl_card_active param is missing' do
      it 'adds an error and returns unprocessable_content' do
        patch :update_spl_card_activate,
              params: { public_metadata: {} },
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(order.errors[:base]).to include(
          I18n.t('order.loyalty_card_missing')
        )
      end
    end

    context 'when spl_card_active param is present' do
      before do
        create(:promotion, orders: [order])
      end

      it 'updates order metadata, clears promotions and runs promotion switcher' do
        patch :update_spl_card_activate,
              params: { public_metadata: { spl_card_active: 'false' } },
              as: :json

        order.reload

        expect(order.public_metadata['spl_card_active']).to eq(false)
        expect(order.promotions).to be_empty
        expect(PromotionSwitcherService)
          .to have_received(:new).with(order, true)
      end
    end
  end
end
