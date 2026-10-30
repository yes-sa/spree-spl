# frozen_string_literal: true

module Spl
  # Single entry point for the loyalty data SPL keeps on Spree metafields.
  #
  #   spl.card_number           ShortText   Spree::Order, user
  #   spl.card_active           Boolean     Spree::Order, user
  #   consent.accept_spl_terms  Boolean     user
  #
  # Nothing here reads `public_metadata`. `rake spl:backfill_metafields` moves
  # the legacy keys onto these metafields and is the only place that still
  # knows they ever existed, so it has to run before the gem is deployed.
  class Metafields
    CARD_NUMBER = 'spl.card_number'
    CARD_ACTIVE = 'spl.card_active'
    ACCEPT_TERMS = 'consent.accept_spl_terms'

    DEFINITIONS = {
      CARD_NUMBER => { name: 'SPL card number', metafield_type: 'Spree::Metafields::ShortText' },
      CARD_ACTIVE => { name: 'SPL card active', metafield_type: 'Spree::Metafields::Boolean' },
      ACCEPT_TERMS => { name: 'SPL terms accepted', metafield_type: 'Spree::Metafields::Boolean' }
    }.freeze

    class << self
      def card_number(resource)
        read(resource, CARD_NUMBER)
      end

      def card_number?(resource)
        card_number(resource).present?
      end

      def set_card_number(resource, value)
        write(resource, CARD_NUMBER, value.presence&.to_s)
      end

      # true, false, or nil when the card state was never set on the resource.
      def card_active(resource)
        read(resource, CARD_ACTIVE)
      end

      def card_active?(resource)
        card_active(resource) == true
      end

      def card_active_set?(resource)
        !card_active(resource).nil?
      end

      def set_card_active(resource, value)
        write(resource, CARD_ACTIVE, value)
      end

      # true, false, or nil when the consent was never recorded.
      def accept_terms(resource)
        read(resource, ACCEPT_TERMS)
      end

      def accept_terms?(resource)
        accept_terms(resource) == true
      end

      def set_accept_terms(resource, value)
        write(resource, ACCEPT_TERMS, value)
      end

      # The user a card belongs to, looked up in SQL - never by loading every
      # user into memory.
      def user_with_card_number(card_number)
        return if card_number.blank?

        users_with_card_number(card_number).first
      end

      def card_assigned_to_other_user?(card_number, user)
        return false if card_number.blank?

        users_with_card_number(card_number, except: user).exists?
      end

      def ensure_definitions!
        DEFINITIONS.each_key do |full_key|
          resource_types(full_key).each { |resource_type| definition(resource_type, full_key) }
        end
      end

      def resource_types(full_key)
        return [::Spree.user_class.to_s] if full_key == ACCEPT_TERMS

        [::Spree::Order.to_s, ::Spree.user_class.to_s]
      end

      private

      def users_with_card_number(card_number, except: nil)
        scope = ::Spree.user_class.with_metafield_key_value(CARD_NUMBER, card_number)
        except&.id ? scope.where.not(id: except.id) : scope
      end

      # `value` is the raw text column, so a Boolean metafield reads back as
      # "true" / "false"; `serialize_value` is the typed subclass's own
      # deserialization and hands back a real boolean.
      def read(resource, full_key)
        metafield_for(resource, full_key)&.serialize_value
      end

      def metafield_for(resource, full_key)
        return unless resource.respond_to?(:metafields) && resource.persisted?

        namespace, key = full_key.split('.')
        resource.metafields.joins(:metafield_definition)
                .find_by(spree_metafield_definitions: { namespace: namespace, key: key })
      end

      def write(resource, full_key, value)
        return if resource.nil?

        definition = definition_for(resource, full_key)
        record = definition.metafield_type.constantize.find_or_initialize_by(
          resource: resource, metafield_definition: definition
        )

        if value.nil?
          record.destroy! if record.persisted?
        else
          # The typed subclass normalizes on assignment, so a Boolean metafield
          # coerces 'true' / true / '1' to its canonical "true" by itself.
          record.value = value
          record.save! if record.changed?
        end
      end

      def definition_for(resource, full_key)
        definition(resource.class.base_class.to_s, full_key)
      end

      def definition(resource_type, full_key)
        namespace, key = full_key.split('.')
        attributes = DEFINITIONS.fetch(full_key)

        ::Spree::MetafieldDefinition.find_or_create_by!(
          resource_type: resource_type,
          namespace: namespace,
          key: key
        ) do |record|
          record.name = attributes[:name]
          record.metafield_type = attributes[:metafield_type]
          record.display_on = 'both'
        end
      end
    end
  end
end
