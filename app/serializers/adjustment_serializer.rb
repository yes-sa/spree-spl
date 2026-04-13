# frozen_string_literal: true

if defined?(Spree::V2::Storefront::BaseSerializer)
  class AdjustmentSerializer < Spree::V2::Storefront::BaseSerializer
    set_type :adjustment

    attributes :label, :amount, :display_amount, :eligible, :created_at, :updated_at
  end
else
  # Spree 5.4+ — V2 serializer is not used, define empty class to avoid NameError
  class AdjustmentSerializer; end # rubocop:disable Lint/EmptyClass
end
