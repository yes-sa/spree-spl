# frozen_string_literal: true

module V3
  module CartSerializerDecorator
    def self.prepended(base)
      base.many :adjustments, resource: V3::AdjustmentSerializer do |cart|
        cart.line_items.map(&:adjustments).flatten.uniq
      end
    end
  end
end
