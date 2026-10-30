# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::OrderUpdater, type: :model do
  let(:store) { Spree::Store.default || create(:store, default: true) }

  let!(:order) do
    create(
      :order,
      store: store,
      payment_state: payment_state,
      state: order_state
    )
  end
  let(:adjustments) { [] }

  let(:payment_state)  { nil }
  let(:order_state)    { 'cart' }

  subject(:updater) { described_class.new(order) }

  before do
    allow(UpdateSpartaStateJob).to receive(:perform_later)
  end

  describe '#update' do
    context "when payment_state is 'paid'" do
      let(:payment_state) { 'paid' }

      it "calls UpdateSpartaStateJob with 'D'" do
        updater.send(:perform_update_sparta_state_job)

        expect(UpdateSpartaStateJob).to have_received(:perform_later).with(
          order.token,
          'D',
          order.number,
          order.store
        )
      end
    end

    context "when order is 'canceled'" do
      let(:order_state) { 'canceled' }

      it "calls UpdateSpartaStateJob with 'C'" do
        updater.send(:perform_update_sparta_state_job)

        expect(UpdateSpartaStateJob).to have_received(:perform_later).with(
          order.token,
          'C',
          order.number,
          order.store
        )
      end
    end

    context 'when both paid and canceled' do
      let(:payment_state) { 'paid' }
      let(:order_state)   { 'canceled' }

      it 'calls the job twice with both states' do
        updater.send(:perform_update_sparta_state_job)

        expect(UpdateSpartaStateJob).to have_received(:perform_later).with(
          order.token, 'D', order.number, order.store
        )

        expect(UpdateSpartaStateJob).to have_received(:perform_later).with(
          order.token, 'C', order.number, order.store
        )
      end
    end

    context 'when neither paid nor canceled' do
      let(:payment_state) { 'balance_due' }
      let(:order_state)   { 'complete' }

      it 'does not call UpdateSpartaStateJob' do
        updater.send(:perform_update_sparta_state_job)

        expect(UpdateSpartaStateJob).not_to have_received(:perform_later)
      end
    end
  end
end
