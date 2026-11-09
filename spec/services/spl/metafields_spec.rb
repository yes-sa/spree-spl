# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spl::Metafields do
  let(:user) { create(:user) }
  let(:order) { create(:order) }

  def definition_for(resource_type, full_key)
    namespace, key = full_key.split('.')
    Spree::MetafieldDefinition.find_by(resource_type: resource_type, namespace: namespace, key: key)
  end

  describe '.ensure_definitions!' do
    before { described_class.ensure_definitions! }

    it 'defines the card number as short text on orders and users' do
      expect(definition_for('Spree::Order', described_class::CARD_NUMBER).metafield_type)
        .to eq('Spree::Metafields::ShortText')
      expect(definition_for(Spree.user_class.to_s, described_class::CARD_NUMBER).metafield_type)
        .to eq('Spree::Metafields::ShortText')
    end

    it 'defines the card state as a boolean' do
      expect(definition_for('Spree::Order', described_class::CARD_ACTIVE).metafield_type)
        .to eq('Spree::Metafields::Boolean')
    end

    it 'defines the terms consent as a boolean on users only' do
      expect(definition_for(Spree.user_class.to_s, described_class::ACCEPT_TERMS).metafield_type)
        .to eq('Spree::Metafields::Boolean')
      expect(definition_for('Spree::Order', described_class::ACCEPT_TERMS)).to be_nil
    end

    it 'is idempotent' do
      expect { described_class.ensure_definitions! }.not_to change(Spree::MetafieldDefinition, :count)
    end
  end

  describe 'card number' do
    it 'round-trips through a metafield' do
      described_class.set_card_number(order, '1234567890123')

      expect(described_class.card_number(order)).to eq('1234567890123')
      expect(order.metafields.reload.first.value).to eq('1234567890123')
    end

    it 'is nil until it is set' do
      expect(described_class.card_number(order)).to be_nil
      expect(described_class.card_number?(order)).to be(false)
    end

    it 'clears the metafield when given a blank value' do
      described_class.set_card_number(order, '1234567890123')
      described_class.set_card_number(order, '')

      expect(described_class.card_number(order)).to be_nil
      expect(order.metafields.reload).to be_empty
    end

    it 'never reads public_metadata' do
      order.update!(public_metadata: { 'spl_no_card' => '1234567890123' })

      expect(described_class.card_number(order)).to be_nil
    end
  end

  describe 'card state' do
    it 'stores booleans as canonical strings' do
      described_class.set_card_active(order, 'true')

      expect(order.metafields.reload.first.value).to eq('true')
      expect(described_class.card_active(order)).to be(true)
    end

    it 'lets the metafield type coerce whatever the params carried' do
      described_class.set_card_active(order, '1')
      expect(described_class.card_active(order)).to be(true)

      described_class.set_card_active(order, 'false')
      expect(described_class.card_active(order)).to be(false)
    end

    it 'is nil until it is set' do
      expect(described_class.card_active(order)).to be_nil
      expect(described_class.card_active_set?(order)).to be(false)
      expect(described_class.card_active?(order)).to be(false)
    end

    it 'does not rewrite an unchanged value' do
      described_class.set_card_active(order, true)
      metafield = order.metafields.reload.first

      expect { described_class.set_card_active(order, true) }
        .not_to(change { metafield.reload.updated_at })
    end

    it 'clears the key when given nil' do
      described_class.set_card_active(order, true)
      described_class.set_card_active(order, nil)

      expect(described_class.card_active(order)).to be_nil
      expect(described_class.card_active_set?(order)).to be(false)
    end

    it 'returns nil for a resource that has no card at all' do
      expect(described_class.card_active(nil)).to be_nil
      expect(described_class.card_number(nil)).to be_nil
    end
  end

  describe 'terms consent' do
    it 'round-trips through a metafield' do
      described_class.set_accept_terms(user, true)

      expect(described_class.accept_terms?(user)).to be(true)
    end

    it 'is false when nothing was ever stored' do
      expect(described_class.accept_terms?(user)).to be(false)
    end

    it 'reports an unrecorded consent as nil, not false' do
      expect(described_class.accept_terms(user)).to be_nil

      described_class.set_accept_terms(user, false)

      expect(described_class.accept_terms(user)).to be(false)
    end

    it 'clears the consent when given nil' do
      described_class.set_accept_terms(user, true)
      described_class.set_accept_terms(user, nil)

      expect(described_class.accept_terms(user)).to be_nil
    end
  end

  describe '.user_with_card_number' do
    let!(:other_user) { create(:user) }

    it 'finds the owner by metafield' do
      described_class.set_card_number(user, '1234567890123')

      expect(described_class.user_with_card_number('1234567890123')).to eq(user)
    end

    it 'queries the database instead of loading every user' do
      described_class.set_card_number(user, '1234567890123')

      expect(Spree.user_class).not_to receive(:find)
      expect(described_class.user_with_card_number('1234567890123')).to eq(user)
    end

    it 'returns nil for a blank or unknown card number' do
      expect(described_class.user_with_card_number('')).to be_nil
      expect(described_class.user_with_card_number('0000000000000')).to be_nil
    end
  end

  describe '.card_assigned_to_other_user?' do
    let!(:other_user) { create(:user) }

    it 'is false when the card belongs to the given user' do
      described_class.set_card_number(user, '1234567890123')

      expect(described_class.card_assigned_to_other_user?('1234567890123', user)).to be(false)
    end

    it 'is true when another user holds the card' do
      described_class.set_card_number(other_user, '1234567890123')

      expect(described_class.card_assigned_to_other_user?('1234567890123', user)).to be(true)
    end

    it 'is false when nobody holds the card' do
      expect(described_class.card_assigned_to_other_user?('1234567890123', user)).to be(false)
    end
  end
end
