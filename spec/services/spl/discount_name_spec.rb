# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spl::DiscountName do
  describe '.customer_label' do
    it 'strips a trade-agreement prefix without a space after the dot' do
      expect(described_class.customer_label('123L.Dla Patryka')).to eq('Dla Patryka')
    end

    it 'strips a trade-agreement prefix with a space after the dot' do
      expect(described_class.customer_label('K1. Dla Patryka')).to eq('Dla Patryka')
    end

    it 'uses preferred trade agreement number when provided' do
      expect(
        described_class.customer_label(
          'V468#1.Kupon 20%',
          trade_agreement_number: 'V468#1'
        )
      ).to eq('Kupon 20%')
    end

    it 'returns the original name when no prefix is present' do
      expect(described_class.customer_label('Dla Patryka')).to eq('Dla Patryka')
    end
  end
end
