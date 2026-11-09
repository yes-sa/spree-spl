# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::LineItemsController, type: :controller do
  let(:state) { create(:state, country: create(:country_us), name: 'Gdansk', abbr: 'GDA') }
  let(:store) { create(:store) }
  let(:variant) { create(:variant, product: create(:product, stores: [store])) }
  let(:user)  { create(:user) }
  let(:order) { create(:order, user: user, store: store) }

  before do
    allow(controller).to receive(:current_store).and_return(store)
    allow(controller).to receive(:spree_current_user).and_return(user)
    allow(controller).to receive(:spree_current_order).and_return(order)
  end

  describe 'POST #create #add_spl_discount_params_to_order' do
    context 'when the user has an SPL card' do
      before do
        Spl::Metafields.set_card_number(user, '1234567890123')
        Spl::Metafields.set_card_active(user, true)
      end

      it 'copies the SPL card onto the order metafields' do
        post :create, params: { variant_id: variant.id, quantity: 1 }
        order.reload

        expect(Spl::Metafields.card_number(order)).to eq('1234567890123')
        expect(Spl::Metafields.card_active(order)).to be(true)
      end
    end

    context 'when SPL card is inactive' do
      before do
        Spl::Metafields.set_card_number(user, '1234567890123')
        Spl::Metafields.set_card_active(user, false)
      end

      it 'casts spl_card_active to boolean false' do
        post :create, params: { variant_id: variant.id, quantity: 1 }
        order.reload

        expect(Spl::Metafields.card_active(order)).to be(false)
      end
    end

    context 'when the user has no SPL card' do
      it 'does not touch the order card' do
        post :create, params: { variant_id: variant.id, quantity: 1 }
        order.reload

        expect(Spl::Metafields.card_number(order)).to be_nil
      end
    end

    context 'when user is nil' do
      before { allow(controller).to receive(:spree_current_user).and_return(nil) }

      it 'does not raise and does not touch the order card' do
        expect { post :create, params: { variant_id: variant.id, quantity: 1 } }.not_to raise_error
        order.reload

        expect(Spl::Metafields.card_number(order)).to be_nil
      end
    end
  end
end
