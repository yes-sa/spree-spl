# frozen_string_literal: true

# The loyalty card used to ride along in `public_metadata`, which the account
# payload exposes. It lives on metafields now, and the user serializer - unlike
# the cart and order ones - does not expose them on its own.
module UserSerializerDecorator
  def self.prepended(base)
    base.include ::Spree::Api::V2::PublicMetafieldsConcern
  end
end
