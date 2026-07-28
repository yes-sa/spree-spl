# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplySpartaDiscountService, type: :service do
  let(:country) { create(:country) }
  let(:store)    { create(:store, default_country: country) }
  let(:order)    { create(:order, store: store) }

  let(:variant1) { create(:variant, price: 6.75,  sku: 'BS49252-BZ020-PSA000-000') }
  let(:variant2) { create(:variant, price: 7.73,  sku: 'BS49252-BZ020-PSA000-001') }

  let!(:line_item1) { create(:line_item, order: order, variant: variant1, quantity: 1, price: 6.75) }
  let!(:line_item2) { create(:line_item, order: order, variant: variant2, quantity: 3, price: 7.73) }

  let(:base_response) do
    {
      'errorCode' => '0',
      'response' => {
        'basket' => sparta_basket
      }
    }
  end

  let(:sparta_basket) do
    [
      {
        'productCode' => 'TESTPRD1',
        'quantity' => 1.0,
        'amountGross' => 6.75,
        'discountGross' => 0.0,
        'discounts' => nil,
        'pos' => line_item1.id
      },
      {
        'productCode' => 'TESTPRD4',
        'quantity' => 3.0,
        'amountGross' => 23.2,
        'discountGross' => 0.8,
        'discounts' => [
          {
            'name' => 'K2555L. Choose your benefit 2025 -600 Kč při nákupu od 3 000 Kč',
            'amount' => 0.8
          }
        ],
        'pos' => line_item2.id
      }
    ]
  end

  let(:service) { described_class.new(base_response, order) }

  before do
    allow(RemoveSpartaDiscountService).to receive(:destroy_inactive_adjustments)
    allow(Spree::Dependencies).to receive(:cart_recalculate_service).and_return('FakeCartRecalculateService')
    stub_const('FakeCartRecalculateService', Class.new do
      def self.call(order:, line_item: nil); end
    end)
  end

  describe '#call' do
    it 'creates SPL adjustment for discounted items' do
      service.call

      adj = line_item2.adjustments.select { |a| a.preferred_external_source_type == 'SPL' }.first

      expect(adj).not_to be_nil
      expect(adj.amount).to eq(-0.8)
      expect(adj.label).to eq('Choose your benefit 2025 -600 Kč při nákupu od 3 000 Kč')
      expect(adj.preferred_external_source_type).to eq('SPL')
      expect(adj.preferred_trade_agreement_number).to eq('K2555L')
      expect(adj.preferred_external_name).to eq('K2555L. Choose your benefit 2025 -600 Kč při nákupu od 3 000 Kč')
    end

    it 'does NOT create adjustment for items with no discounts' do
      service.call

      expect(line_item1.adjustments.select { |a| a.preferred_external_source_type == 'SPL' }).to be_empty
    end

    context 'with extra adjustment' do
      before do
        adj = create(:adjustment,
                     external_source_type: 'Promotion',
                     amount: -5,
                     label: 'OLD_PROMO',
                     order: order,
                     adjustable: line_item2)
        line_item2.update(adjustments: [adj])
      end
      it 'removes non-SPL promotion adjustments before creating SPL discount' do
        expect do
          service.call
        end.to change { line_item2.adjustments.reload.select { |a| a.preferred_external_source_type == 'SPL' }.count }.by(1)
        expect(line_item2.adjustments.where(label: 'OLD_PROMO')).to be_empty
      end
    end

    it 'updates existing SPL adjustment instead of creating a new one' do
      existing = line_item2.adjustments.create!(
        preferred_external_source_type: 'SPL',
        amount: -0.5,
        label: 'Choose your benefit 2025 -600 Kč při nákupu od 3 000 Kč',
        order: order
      )

      service.call

      existing.reload
      expect(existing.amount).to eq(-0.8)
      expect(line_item2.adjustments.select { |a| a.preferred_external_source_type == 'SPL' }.count).to eq(1)
    end

    context 'when multi_coupon_adjustments is enabled' do
      before do
        Spree::Spl.config.multi_coupon_adjustments = true
      end

      after do
        Spree::Spl.config.multi_coupon_adjustments = false
      end

      it 'updates existing SPL adjustment by preferred_external_name' do
        external_name = 'K2555L. Choose your benefit 2025 -600 Kč při nákupu od 3 000 Kč'
        existing = line_item2.adjustments.create!(
          preferred_external_source_type: 'SPL',
          preferred_external_name: external_name,
          preferred_trade_agreement_number: 'K2555L',
          amount: -0.5,
          label: 'Choose your benefit 2025 -600 Kč při nákupu od 3 000 Kč',
          order: order,
          adjustable: line_item2
        )

        service.call

        existing.reload
        expect(existing.amount).to eq(-0.8)
        expect(line_item2.adjustments.select { |a| a.preferred_external_source_type == 'SPL' }.count).to eq(1)
      end

      it 'creates one adjustment per coupon when Sparta returns multiple discounts' do
        sparta_basket[1]['discountGross'] = 1.5
        sparta_basket[1]['discounts'] = [
          { 'name' => '123L.Dla Patryka', 'amount' => 0.8 },
          { 'name' => 'V468#1.Kupon 20%', 'amount' => 0.7 }
        ]

        service.call

        labels = line_item2.adjustments.select { |a| a.preferred_external_source_type == 'SPL' }.map(&:label)
        expect(labels).to contain_exactly('Dla Patryka', 'Kupon 20%')
      end
    end

    it 'removes SPL adjustments if Sparta discount becomes nil' do
      line_item2.adjustments.create!(
        preferred_external_source_type: 'SPL',
        amount: -0.8,
        label: 'Choose your benefit 2025 -600 Kč při nákupu od 3 000 Kč',
        order: order
      )

      sparta_basket[1]['discounts'] = nil
      sparta_basket[1]['discountGross'] = 0.0
      expect(RemoveSpartaDiscountService).to receive(:destroy_inactive_adjustments)

      service.call
    end

    it 'does nothing when errorCode != 0' do
      base_response['errorCode'] = '123'

      expect(line_item2.adjustments).to be_empty

      service.call

      expect(line_item2.adjustments).to be_empty
    end

    it "does nothing when response['basket'] is missing" do
      base_response['response']['basket'] = nil

      service.call

      expect(line_item2.adjustments).to be_empty
    end
  end
end
