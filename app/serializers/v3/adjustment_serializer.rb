# frozen_string_literal: true

module V3
  class AdjustmentSerializer < Spree::Api::V3::BaseSerializer
    attributes :label, :amount, :display_amount, :eligible, :created_at, :updated_at
  end
end
