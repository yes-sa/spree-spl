# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spl::ManualCoupons::ApplyService do
  let(:store) { create(:store) }
  let(:order) { create(:order, store: store) }

  around do |example|
    previous = Spree::Spl.config.manual_discount_codes
    Spree::Spl.config.manual_discount_codes = true
    example.run
  ensure
    Spree::Spl.config.manual_discount_codes = previous
  end

  before { create(:line_item, order: order) }

  it 'rejects invalid format without calling SPL' do
    expect(Spl::RecalculateOrderService).not_to receive(:new)

    result = described_class.new(order, 'bad code!').call

    expect(result).not_to be_success
    expect(result.error_key).to eq('invalid_format')
    expect(Spl::ManualCoupons.for_order(order.reload)).to be_empty
  end

  it 'stores code and recalculates when SPL does not mark it invalid' do
    allow(RemoveSpartaDiscountService).to receive(:destroy_all_sparta_adjustments)
    recalculator = instance_double(Spl::RecalculateOrderService, call: order)
    allow(Spl::RecalculateOrderService).to receive(:new).and_return(recalculator)
    allow(Spl::RecalculateOrderService).to receive(:bump_coupon_version!)

    result = described_class.new(order, 'verona10').call

    expect(result).to be_success
    expect(result.code).to eq('VERONA10')
    expect(Spl::ManualCoupons.for_order(order.reload)).to eq(['VERONA10'])
    expect(recalculator).to have_received(:call)
  end

  it 'removes code when SPL marks it invalid' do
    allow(RemoveSpartaDiscountService).to receive(:destroy_all_sparta_adjustments)
    recalculator = instance_double(Spl::RecalculateOrderService, call: order)
    allow(Spl::RecalculateOrderService).to receive(:new).and_return(recalculator)
    allow(Spl::RecalculateOrderService).to receive(:bump_coupon_version!)

    allow(Spl::ManualCoupons).to receive(:result_for).and_return(
      { 'code' => 'VERONA10', 'valid' => false, 'nonValidReasons' => ['unknownCode'] }
    )

    result = described_class.new(order, 'VERONA10').call

    expect(result).not_to be_success
    expect(result.error_key).to eq('not_valid')
    expect(result.non_valid_reasons).to eq(['unknownCode'])
    expect(Spl::ManualCoupons.for_order(order.reload)).to be_empty
  end
end
