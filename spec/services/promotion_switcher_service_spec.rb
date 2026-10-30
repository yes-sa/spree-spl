# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PromotionSwitcherService, type: :service do
  let(:country) { create(:country) }
  let(:store) { create(:store, default_country: country) }
  let(:order) { create(:order, store:) }

  let(:card_number) { nil }
  let(:card_active) { nil }

  let(:check_only) { true }

  let(:service) { described_class.new(order, check_only) }

  let(:variant1) { create(:variant, sku: 'BS49252-BZ020-PSA000-000', price: 6.75) }
  let(:variant2) { create(:variant, sku: 'BS49252-BZ020-PSA000-001', price: 7.73) }

  let!(:line_item1) { create(:line_item, order:, variant: variant1, quantity: 1, price: 6.75) }
  let!(:line_item2) { create(:line_item, order:, variant: variant2, quantity: 3, price: 7.73) }

  before do
    Spl::Metafields.set_card_number(order, card_number)
    Spl::Metafields.set_card_active(order, card_active)
  end

  let(:example_sparta_response) do
    {
      'errorCode' => '0',
      'balanceBurn' => 0.0,
      'balanceEarn' => 0.0,
      'balanceAfter' => 0.12,
      'bookedEarn' => false,
      'processId' => '663c92b05012e0b396ac632b',
      'messages' => [],
      'basket' => [
        {
          'productCode' => 'TESTPRD1',
          'productCode2' => nil,
          'quantity' => 1.0,
          'amountGross' => 6.75,
          'discountGross' => 0.0,
          'discountPercent' => nil,
          'unitPriceGross' => 6.75,
          'discounts' => nil,
          'isAward' => nil,
          'notPromoted' => nil,
          'skipCB' => nil,
          'skipDD' => nil,
          'skipRD' => nil,
          'pos' => 1
        },
        {
          'productCode' => 'TESTPRD4',
          'productCode2' => nil,
          'quantity' => 3.0,
          'amountGross' => 23.2,
          'discountGross' => 0.8,
          'discountPercent' => nil,
          'unitPriceGross' => 7.73,
          'discounts' => [
            {
              'source' => 'LP',
              'amount' => 0.8,
              'percent' => 5.0,
              'code' => '663c926e5012e0b396ac6328',
              'name' => '5% discount for TESTPRD4',
              'order' => 1,
              'quantity' => 2.0,
              'unitPriceGrossDiscounted' => nil
            }
          ],
          'isAward' => nil,
          'notPromoted' => nil,
          'skipCB' => nil,
          'skipDD' => nil,
          'skipRD' => nil,
          'pos' => 2
        }
      ],
      'basketChanged' => true,
      'amountGross' => 29.95,
      'discountGross' => 0.8,
      'coupons' => [],
      'cardType' => { 'code' => 'DV' },
      'requestId' => '00003_LSHRV'
    }
  end

  describe '#call' do
    let(:country) { create(:country) }
    let(:store) { create(:store, default_country: country) }

    let(:card_number) { '5100179585157' }
    let(:card_active) { true }

    it 'calls Sparta loyalty, gets response and applies Sparta discounts' do
      sparta_service_double = instance_double(Spl::SpartaLoyaltyService)
      apply_service_double  = instance_double(ApplySpartaDiscountService)

      expect(Spl::SpartaLoyaltyService).to receive(:new).and_return(sparta_service_double)
      expect(sparta_service_double).to receive(:call).once.and_return(example_sparta_response)
      expect(ApplySpartaDiscountService).to receive(:new)
        .with(example_sparta_response, order)
        .and_return(apply_service_double)
      expect(apply_service_double).to receive(:call).once

      service.call
    end

    context 'when spl_card_active is true but Sparta returns nil' do
      let(:card_number) { '5100179585157' }
      let(:card_active) { true }

      it 'does not apply Sparta discounts (but still reloads the order)' do
        sparta_service_double = instance_double(Spl::SpartaLoyaltyService)

        expect(Spl::SpartaLoyaltyService).to receive(:new).and_return(sparta_service_double)
        expect(sparta_service_double).to receive(:call).and_return(nil)

        expect(ApplySpartaDiscountService).not_to receive(:new)

        service.call
      end
    end

    context 'when spl_card_active is false' do
      let(:card_number) { '5100179585157' }
      let(:card_active) { false }

      it 'calls Sparta with empty card number and does not apply discounts' do
        sparta_service_double = instance_double(Spl::SpartaLoyaltyService)

        expect(Spl::SpartaLoyaltyService).to receive(:new) do |_, card_no, *_|
          expect(card_no).to eq('')
          sparta_service_double
        end

        expect(sparta_service_double).to receive(:call).and_return(nil)
        expect(ApplySpartaDiscountService).not_to receive(:new)

        service.call
      end
    end

    context 'when there are no line items' do
      let(:card_number) { '5100179585157' }
      let(:card_active) { true }

      before do
        order.line_items.destroy_all
      end

      it 'does not call Sparta loyalty service or apply discounts' do
        expect(Spl::SpartaLoyaltyService).not_to receive(:new)
        expect(ApplySpartaDiscountService).not_to receive(:new)

        service.call
      end
    end

    context 'when spl_card_active is true but card number is missing' do
      let(:card_number) { nil }
      let(:card_active) { true }

      it 'calls Sparta with nil card number and does not apply discounts' do
        sparta_service_double = instance_double(Spl::SpartaLoyaltyService)

        expect(Spl::SpartaLoyaltyService).to receive(:new) do |_, card_no, *_|
          expect(card_no).to be_nil
          sparta_service_double
        end

        expect(sparta_service_double).to receive(:call).and_return(nil)
        expect(ApplySpartaDiscountService).not_to receive(:new)

        service.call
      end
    end

    context 'when spl_card_active is missing and card number is missing' do
      let(:card_number) { nil }
      let(:card_active) { nil }

      it 'calls Sparta with empty card number and does not apply discounts' do
        sparta_service_double = instance_double(Spl::SpartaLoyaltyService)

        expect(Spl::SpartaLoyaltyService).to receive(:new) do |_, card_no, *_|
          expect(card_no).to eq('')
          sparta_service_double
        end

        expect(sparta_service_double).to receive(:call).and_return(nil)
        expect(ApplySpartaDiscountService).not_to receive(:new)

        service.call
      end
    end
  end
end
