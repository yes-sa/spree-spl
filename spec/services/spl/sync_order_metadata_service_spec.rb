# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spl::SyncOrderMetadataService do
  let(:user) { create(:user) }
  let(:order) { create(:order, user: user) }

  before do
    Spl::Metafields.set_card_number(user, '5100179585157')
    Spl::Metafields.set_card_active(user, true)
  end

  it 'copies the SPL card from the user onto the order' do
    described_class.new(order, user).call

    expect(Spl::Metafields.card_number(order)).to eq('5100179585157')
    expect(Spl::Metafields.card_active(order)).to be(true)
  end

  it 'does nothing when the user has no SPL card' do
    Spl::Metafields.set_card_number(user, nil)
    Spl::Metafields.set_card_active(user, nil)

    described_class.new(order, user).call

    expect(Spl::Metafields.card_number(order)).to be_nil
    expect(Spl::Metafields.card_active(order)).to be_nil
  end

  it 'does not write when the card is already in sync' do
    Spl::Metafields.set_card_number(order, '5100179585157')
    Spl::Metafields.set_card_active(order, true)

    expect(Spl::Metafields).not_to receive(:set_card_number)
    expect(Spl::Metafields).not_to receive(:set_card_active)

    described_class.new(order, user).call
  end
end
