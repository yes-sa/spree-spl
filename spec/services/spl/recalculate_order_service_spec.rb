# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spl::RecalculateOrderService do
  let(:country) { create(:country) }
  let(:store) { create(:store, default_country: country) }
  let(:user) { create(:user) }
  let(:order) { create(:order, store: store, user: user) }
  let(:metadata_sync) { instance_double(Spl::SyncOrderMetadataService, call: true) }
  let(:switcher) { instance_double(PromotionSwitcherService, call: :success) }

  before do
    Spl::Metafields.set_card_number(user, '5100179585157')
    Spl::Metafields.set_card_active(user, true)
    allow(Spl::SyncOrderMetadataService).to receive(:new).and_return(metadata_sync)
    allow(PromotionSwitcherService).to receive(:new).and_return(switcher)
    Spree::Spl.config.promotion_switcher_status_result = true
  end

  after do
    Spree::Spl.config.promotion_switcher_status_result = false
  end

  it 'syncs metadata and runs promotion switcher in check-only mode' do
    create(:line_item, order: order)

    described_class.new(order, user: user, store: store).call

    expect(metadata_sync).to have_received(:call)
    expect(switcher).to have_received(:call)
  end

  it 'skips when order has no line items' do
    expect(PromotionSwitcherService).not_to receive(:new)

    described_class.new(order, user: user, store: store).call
  end

  it 'skips SPL when basket fingerprint is unchanged' do
    create(:line_item, order: order)
    service = described_class.new(order, user: user, store: store)
    fingerprint = service.send(:basket_fingerprint)
    order.update!(private_metadata: { 'spl_basket_fingerprint' => fingerprint })

    expect(PromotionSwitcherService).not_to receive(:new)

    service.call
  end

  it 'calls SPL when force is true even if fingerprint matches' do
    create(:line_item, order: order)
    service = described_class.new(order, user: user, store: store, force: true)
    fingerprint = service.send(:basket_fingerprint)
    order.update!(private_metadata: { 'spl_basket_fingerprint' => fingerprint })

    described_class.new(order, user: user, store: store, force: true).call

    expect(switcher).to have_received(:call)
  end

  it 'changes the basket fingerprint when the card state on the order changes' do
    create(:line_item, order: order)
    fingerprint = described_class.new(order, user: user, store: store).send(:basket_fingerprint)

    Spl::Metafields.set_card_active(order, true)

    expect(described_class.new(order.reload, user: user, store: store).send(:basket_fingerprint))
      .not_to eq(fingerprint)
  end
end
