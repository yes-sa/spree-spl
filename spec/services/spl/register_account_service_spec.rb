# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spl::RegisterAccountService do
  subject(:service) { described_class.new(user, store, params) }

  let(:store) do
    create(
      :store,
      default_country: create(:country),
      private_metadata: {
        'spl_url' => 'https://spl.test',
        'spl_prg_code' => 'PRG',
        'spl_partner_code' => 'PARTNER',
        'spl_place_code' => 'PLACE'
      }
    )
  end

  let(:user) do
    create(
      :user,
      phone: '+48500600700',
      first_name: 'John',
      last_name: 'Doe',
      email: 'john@example.com',
      public_metadata: { 'accept_yc_terms' => true },
      private_metadata: {}
    )
  end

  let(:params) { '123456' }
  let(:phone_parser) { instance_double(PhoneParserService, country_code: '+48', national_number: '500600700') }
  let(:oauth_response) { { 'response' => { 'accessToken' => 'ACCESS_TOKEN', 'refreshToken' => 'REFRESH_TOKEN' } } }
  let(:register_response_body) { { 'errorCode' => '0', 'response' => { 'cardNo' => 'CARD123' } } }
  let(:http_response) { instance_double(Net::HTTPResponse, body: register_response_body.to_json) }
  let(:send_request_service) { instance_double(Spl::SendRequestService, call: http_response) }

  before do
    allow(PhoneParserService).to receive(:new).and_return(phone_parser)
    allow(Spl::OauthTokenService).to receive(:new).and_return(
      instance_double(Spl::OauthTokenService, annonymus_token: oauth_response)
    )
    allow(Spl::SendRequestService).to receive(:new).and_return(send_request_service)
  end

  describe '#call' do
    context 'when registration succeeds' do
      it 'updates user public_metadata with SPL card data' do
        service.call

        expect(user.public_metadata).to include(
          'spl_no_card' => 'CARD123',
          'spl_card_active' => true
        )
      end

      it 'updates user private_metadata with tokens' do
        service.call

        expect(user.private_metadata).to include('spl_access_token' => 'ACCESS_TOKEN', 'spl_refresh_token' => 'REFRESH_TOKEN')
      end

      it 'sends correct payload to SendRequestService' do
        expect(Spl::SendRequestService).to receive(:new) do |url, body|
          expect(url.to_s).to include('register')
          expect(body).to include(authCode: params, partnerCode: 'PARTNER', placeCode: 'PLACE')
          expect(body[:context]).to include(oauthToken: 'ACCESS_TOKEN', prgCode: 'PRG')
          expect(body[:person][:permissions]).to eq(processData: true, operationalSms: true)
          expect(body[:person]).to include(
            firstName: 'John',
            lastName: 'Doe',
            email: 'john@example.com',
            mobileCountry: '+48',
            mobile: '500600700'
          )
          expect(body[:person][:permissions]).to eq(processData: true, operationalSms: true)
        end.and_return(send_request_service)

        service.call
      end
    end

    context 'when SPL returns errorCode != 0' do
      let(:register_response_body) { { 'errorCode' => 'TEMPORARY_BLOCKED', 'msg' => 'Temporarily blocked' } }

      it 'raises SplRegisterAccountError with SPL message' do
        expect do
          service.call
        end.to raise_error(Spl::RegisterAccountService::SplRegisterAccountError, register_response_body.to_s)
      end

      it 'does not update user public_metadata' do
        expect do
          service.call
        rescue StandardError
          nil
        end.not_to(change { user.reload.public_metadata })
      end
    end

    context 'when OTP code is not 6 characters' do
      let(:params) { '123' }

      it 'still sends request to SPL (no local validation)' do
        expect(Spl::SendRequestService).to receive(:new).and_return(send_request_service)

        service.call
      end
    end

    context 'when card number is provided and phone is nil' do
      before do
        user.update!(phone: nil, public_metadata: user.public_metadata.merge('spl_no_card' => 'CARD123'))
        allow(PhoneParserService).to receive(:new).with(nil).and_raise(StandardError, 'Phone missing')
      end

      it 'raises error before sending request' do
        expect { service.call }.to raise_error(StandardError, 'Phone missing')
      end

      it 'does not send request to SPL' do
        expect(Spl::SendRequestService).not_to receive(:new)
        expect { service.call }.to raise_error(StandardError)
      end
    end

    context 'when registration response contains otpLoginToken' do
      let(:register_response_body) do
        {
          'errorCode' => '0',
          'response' => {
            'cardNo' => 'CARD123',
            'otpLoginToken' => 'TOKEN_ABC_123'
          }
        }
      end
      let(:login_service) { instance_double(Spl::LoginAccountService) }

      before do
        allow(Spl::LoginAccountService).to receive(:new).with(
          user,
          store,
          { 'user' => { 'spl_auth_code' => 'TOKEN_ABC_123', 'card_number' => 'CARD123' } },
          raw_otp: true
        ).and_return(login_service)
        allow(login_service).to receive(:call)
      end

      it 'triggers LoginAccountService with raw_otp option to automatically upgrade session' do
        expect(login_service).to receive(:call).once
        service.call
      end
    end
  end
end
