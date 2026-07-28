# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spl::SyncOrderMetadataService do
  let(:user) do
    create(:user, public_metadata: { 'spl_no_card' => '5100179585157', 'spl_card_active' => 'true' })
  end
  let(:order) { create(:order, user: user, public_metadata: {}) }

  it 'copies SPL card metadata from user to order' do
    described_class.new(order, user).call

    order.reload
    expect(order.public_metadata).to include(
      'spl_no_card' => '5100179585157',
      'spl_card_active' => true
    )
  end

  it 'does nothing when user has no SPL metadata' do
    user.update!(public_metadata: {})

    expect { described_class.new(order, user).call }.not_to(change { order.reload.public_metadata })
  end

  it 'does not update when metadata is already in sync' do
    order.update!(public_metadata: { 'spl_no_card' => '5100179585157', 'spl_card_active' => true })

    expect(order).not_to receive(:update!)

    described_class.new(order, user).call
  end
end
