# frozen_string_literal: true

module Spl
  class SyncOrderMetadataService
    include BooleanHelper

    def initialize(order, user)
      @order = order
      @user = user
    end

    def call
      return unless @order&.persisted?
      return unless spl_metadata_present?

      order_metadata = @order.public_metadata.to_h.stringify_keys
      spl_no_card = user_metadata['spl_no_card']
      spl_card_active = cast_boolean(user_metadata['spl_card_active'])

      return if order_metadata['spl_no_card'] == spl_no_card &&
                cast_boolean(order_metadata['spl_card_active']) == spl_card_active

      @order.update!(
        public_metadata: order_metadata.merge(
          'spl_no_card' => spl_no_card,
          'spl_card_active' => spl_card_active
        )
      )
    end

    private

    def user_metadata
      @user_metadata ||= @user.public_metadata.to_h.stringify_keys
    end

    def spl_metadata_present?
      @user && user_metadata.key?('spl_no_card') && user_metadata.key?('spl_card_active')
    end
  end
end
