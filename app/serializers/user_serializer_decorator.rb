# frozen_string_literal: true

module UserSerializerDecorator
  def self.prepended(base)
    base.include ::Spree::Api::V2::PublicMetafieldsConcern
  end
end
