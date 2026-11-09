# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AssignSpartaCardNumberService, type: :service do
  let(:country) { create(:country) }
  let(:store) { create(:store, default_country: country) }
  let(:user)  { create(:user) }

  let(:service) { described_class.new(user, store) }

  let(:me_service_double) { instance_double(Spl::MeService) }

  let(:base_me_response) do
    {
      'errorCode' => '0',
      'validationMessages' => nil,
      'fieldValidationMessages' => nil,
      'response' => {
        'mainCard' => main_card_data
      },
      'msg' => 'OK'
    }
  end

  let(:main_card_data) do
    {
      'burnEnabled' => true,
      'cardType' => {
        'id' => '64c0cdde5012af18dd2f4b44',
        'idAsDictLabel' => 'Verona - Default Virtual Card'
      },
      'depositBurnDisabled' => nil,
      'no' => '5100179585157',
      'status' => 'A',
      'statusAsDictLabel' => 'Active'
    }
  end

  before do
    allow(Spl::MeService).to receive(:new).with(user, store).and_return(me_service_double)
    allow(me_service_double).to receive(:call).and_return(base_me_response)
    stub_const('Spree::User', Spree.user_class)
  end

  describe '#call' do
    context 'when main card is active and belongs to the user' do
      it 'assigns card number and marks card as active on metafields' do
        service.call

        expect(Spl::Metafields.card_number(user)).to eq('5100179585157')
        expect(Spl::Metafields.card_active(user)).to be(true)
      end
    end

    context 'when main card is not active' do
      let(:main_card_data) do
        super().merge('status' => 'B')
      end

      it 'raises AssignSpartaCardNumberError with card_not_active message' do
        expect do
          service.call
        end.to raise_error(
          AssignSpartaCardNumberService::AssignSpartaCardNumberError,
          I18n.t('spl.card_validation.errors.card_not_active')
        )

        expect(Spl::MeService).to have_received(:new).with(user, store)
      end
    end

    context 'when card belongs to a different user' do
      let!(:other_user) do
        create(:user).tap { |u| Spl::Metafields.set_card_number(u, '5100179585157') }
      end

      it 'raises AssignSpartaCardNumberError with wrong_owner message' do
        expect do
          service.call
        end.to raise_error(
          AssignSpartaCardNumberService::AssignSpartaCardNumberError,
          I18n.t('spl.card_validation.errors.wrong_owner')
        )

        expect(main_card_data['status']).to eq('A')
      end
    end
  end
end
