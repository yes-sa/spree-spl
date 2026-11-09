# frozen_string_literal: true

require 'rails_helper'

return unless defined?(Spree::Api::V3::Store::CartsController)

RSpec.describe Spree::Api::V3::Store::CartsController, type: :controller do
  let(:store) { Spree::Store.default || create(:store, default: true) }
  let(:user)  { create(:user) }
  let(:order) { create(:order, user: user, store: store) }

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
    context 'when the user holds an SPL card' do
      before do
        Spl::Metafields.set_card_number(user, '0123456789123')
        Spl::Metafields.set_card_active(user, true)
      end

      it 'stamps the card from the user onto the cart' do
        post :create, params: {}, as: :json

        expect(Spl::Metafields.card_number(order)).to eq('0123456789123')
        expect(Spl::Metafields.card_active(order)).to be(true)
      end
    end

    context 'when the user holds no SPL card' do
      it 'leaves the cart without a card' do
        post :create, params: {}, as: :json

        expect(Spl::Metafields.card_number(order)).to be_nil
        expect(Spl::Metafields.card_active(order)).to be_nil
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
    context 'when the card_active param is missing' do
      it 'adds an error and returns unprocessable_content' do
        patch :update_spl_card_activate,
              params: { spl: {} },
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(order.errors[:base]).to include(
          I18n.t('order.loyalty_card_missing')
        )
      end
    end

    context 'when the card_active param is present' do
      before do
        create(:promotion, orders: [order])
      end

      it 'updates the card state, clears promotions and runs promotion switcher' do
        patch :update_spl_card_activate,
              params: { spl: { card_active: 'false' } },
              as: :json

        order.reload

        expect(Spl::Metafields.card_active(order)).to be(false)
        expect(order.promotions).to be_empty
        expect(PromotionSwitcherService)
          .to have_received(:new).with(order, true)
      end
    end
  end
end
