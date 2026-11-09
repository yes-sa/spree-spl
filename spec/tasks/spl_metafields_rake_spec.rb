# frozen_string_literal: true

require 'rails_helper'
require 'rake'

load Spree::Spl::Engine.root.join('lib/tasks/spl_metafields.rake')

RSpec.describe 'spl:backfill_metafields' do
  let(:legacy_user_metadata) do
    { 'spl_no_card' => '1234567890123', 'spl_card_active' => 'true', 'accept_yc_terms' => true, 'other' => 'keep' }
  end

  let!(:user) { create(:user).tap { |u| u.update!(public_metadata: legacy_user_metadata) } }
  let!(:order) do
    create(:order).tap do |o|
      o.update!(public_metadata: { 'spl_no_card' => '5100179585157', 'spl_card_active' => false })
    end
  end

  before { Spl::Metafields.ensure_definitions! }

  describe 'users' do
    before { SplMetafieldsBackfill.users }

    it 'moves the card onto metafields' do
      expect(Spl::Metafields.card_number(user)).to eq('1234567890123')
      expect(Spl::Metafields.card_active(user)).to be(true)
      expect(Spl::Metafields.accept_terms(user)).to be(true)
    end

    it 'drops the migrated keys and keeps the rest of the column' do
      expect(user.reload.public_metadata).to eq('other' => 'keep')
    end

    it 'is idempotent' do
      expect { SplMetafieldsBackfill.users }.not_to change(Spree::Metafield, :count)
    end
  end

  describe 'orders' do
    before { SplMetafieldsBackfill.orders }

    it 'moves the card onto metafields and empties the column' do
      expect(Spl::Metafields.card_number(order)).to eq('5100179585157')
      expect(Spl::Metafields.card_active(order)).to be(false)
      expect(order.reload.public_metadata).to eq({})
    end
  end

  context 'when a record has no legacy keys' do
    let!(:untouched) { create(:order).tap { |o| o.update!(public_metadata: { 'other' => 'keep' }) } }

    it 'leaves it alone' do
      expect { SplMetafieldsBackfill.orders }.not_to(change { untouched.reload.public_metadata })
      expect(untouched.metafields).to be_empty
    end
  end

  context 'when the legacy card state is present but nil' do
    let(:legacy_user_metadata) { { 'spl_no_card' => '1234567890123', 'spl_card_active' => nil } }

    it 'leaves the card state unset rather than storing false' do
      SplMetafieldsBackfill.users

      expect(Spl::Metafields.card_number(user)).to eq('1234567890123')
      expect(Spl::Metafields.card_active(user)).to be_nil
      expect(user.reload.public_metadata).to eq({})
    end
  end
end
