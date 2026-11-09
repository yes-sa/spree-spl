# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::Api::V2::Storefront::CartController, type: :controller do
  let(:store) { Spree::Store.default || create(:store, default: true) }
  let(:user)  { create(:user) }
  let(:order) { create(:order, user: user, store: store) }

  before do
    allow(controller).to receive(:current_store).and_return(store)
    allow(controller).to receive(:spree_current_user).and_return(user)
    allow(controller).to receive(:spree_current_order).and_return(order)
    allow(PromotionSwitcherService).to receive_message_chain(:new, :call)
  end

  describe 'POST #create' do
    context 'when the user has an SPL card' do
      before do
        Spl::Metafields.set_card_number(user, '0123456789123')
        Spl::Metafields.set_card_active(user, true)
      end

      it 'copies the SPL card onto the cart' do
        post :create, as: :json

        expect(Spl::Metafields.card_number(order)).to eq('0123456789123')
        expect(Spl::Metafields.card_active(order)).to be(true)
      end
    end

    context 'when the user has no SPL card' do
      it 'leaves the cart alone' do
        post :create, as: :json

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
    context 'when spl_card_active param is missing' do
      it 'adds an error and returns unprocessable_content' do
        patch :update_spl_card_activate,
              params: {},
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

      it 'updates the card metafield, clears promotions and runs promotion switcher' do
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
