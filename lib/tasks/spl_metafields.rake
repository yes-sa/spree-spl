# frozen_string_literal: true

namespace :spl do
  desc 'Create the SPL metafield definitions and move card data off public_metadata'
  task backfill_metafields: :environment do
    Spl::Metafields.ensure_definitions!

    SplMetafieldsBackfill.users
    SplMetafieldsBackfill.orders

    puts 'SPL metafields backfill complete.'
  end
end

# The only place that still knows the legacy `public_metadata` keys. Each record
# gets its metafields written and the legacy keys dropped in one pass, so the
# task is safe to re-run and leaves nothing for the gem to read.
module SplMetafieldsBackfill
  CARD_NUMBER = 'spl_no_card'
  CARD_ACTIVE = 'spl_card_active'
  ACCEPT_TERMS = 'accept_yc_terms'

  USER_KEYS = [CARD_NUMBER, CARD_ACTIVE, ACCEPT_TERMS].freeze
  ORDER_KEYS = [CARD_NUMBER, CARD_ACTIVE].freeze

  USER_CONDITION = <<~SQL.squish
    public_metadata ->> 'spl_no_card' IS NOT NULL
    OR public_metadata ->> 'spl_card_active' IS NOT NULL
    OR public_metadata ->> 'accept_yc_terms' IS NOT NULL
  SQL

  ORDER_CONDITION = <<~SQL.squish
    public_metadata ->> 'spl_no_card' IS NOT NULL
    OR public_metadata ->> 'spl_card_active' IS NOT NULL
  SQL

  class << self
    def users
      process(Spree.user_class, USER_CONDITION, USER_KEYS) do |user, metadata|
        Spl::Metafields.set_card_number(user, metadata[CARD_NUMBER]) if metadata.key?(CARD_NUMBER)
        Spl::Metafields.set_card_active(user, metadata[CARD_ACTIVE]) if metadata.key?(CARD_ACTIVE)
        Spl::Metafields.set_accept_terms(user, metadata[ACCEPT_TERMS]) if metadata.key?(ACCEPT_TERMS)
      end
    end

    def orders
      process(Spree::Order, ORDER_CONDITION, ORDER_KEYS) do |order, metadata|
        Spl::Metafields.set_card_number(order, metadata[CARD_NUMBER]) if metadata.key?(CARD_NUMBER)
        Spl::Metafields.set_card_active(order, metadata[CARD_ACTIVE]) if metadata.key?(CARD_ACTIVE)
      end
    end

    private

    def process(klass, condition, keys)
      scope = klass.where(condition)
      puts "#{klass.name}: #{scope.count} records with legacy SPL metadata..."

      scope.find_each do |record|
        metadata = record.public_metadata.to_h
        yield(record, metadata)
        # update_column on purpose: dropping the migrated keys must not fire
        # order callbacks or touch timestamps.
        record.update_column(:public_metadata, metadata.except(*keys)) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
