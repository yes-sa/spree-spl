# frozen_string_literal: true

module Spl
  class SyncOrderMetadataService
    def initialize(order, user)
      @order = order
      @user = user
    end

    def call
      return unless @order&.persisted?
      return unless spl_metadata_present?

      card_number = ::Spl::Metafields.card_number(@user)
      card_active = ::Spl::Metafields.card_active?(@user)

      return if ::Spl::Metafields.card_number(@order) == card_number &&
                ::Spl::Metafields.card_active?(@order) == card_active

      ::Spl::Metafields.set_card_number(@order, card_number)
      ::Spl::Metafields.set_card_active(@order, card_active)
    end

    private

    def spl_metadata_present?
      @user && ::Spl::Metafields.card_number?(@user) && ::Spl::Metafields.card_active_set?(@user)
    end
  end
end
