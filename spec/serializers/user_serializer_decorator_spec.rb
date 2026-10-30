# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::V2::Storefront::UserSerializer do
  subject(:payload) { described_class.new(user.reload, include: [:metafields]).serializable_hash }

  let(:user) { create(:user) }

  before do
    Spl::Metafields.set_card_number(user, '1234567890123')
    Spl::Metafields.set_card_active(user, true)
  end

  it 'exposes the loyalty card the account payload used to carry in public_metadata' do
    expect(payload[:data][:relationships].keys).to include(:metafields)
    expect(payload[:included].map { |m| m[:attributes].slice(:key, :value) }).to include(
      { key: 'spl.card_number', value: '1234567890123' },
      { key: 'spl.card_active', value: true }
    )
  end
end
