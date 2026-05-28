# frozen_string_literal: true

require 'rails_helper'
require 'json'
require 'digest'

RSpec.describe Spl::LoginAccountService, type: :service do
  let(:country) { create(:country) }
  let(:user)  { create(:user, phone: phone) }
  let(:store) { create(:store, default_country: country, private_metadata: { 'spl_url' => 'https://spl.test' }) }

  let(:env) do
    {
      'spl_prg_code' => 'PRG',
      'spl_api_user' => 'user'
    }
  end

  let(:login_url) { URI.parse('https://spl.test/login') }

  let(:phone) { '+48123123123' }

  let(:card_number) { nil }
  let(:otp_code) { '123456' }

  let(:params) do
    {
      'user' => {
        'card_number' => card_number,
        'spl_auth_code' => otp_code
      }
    }
  end

  subject(:service) { described_class.new(user, store, params) }

  let(:send_request_service) { instance_double(Spl::SendRequestService) }
  let(:oauth_service) { instance_double(Spl::OauthTokenService) }

  let(:login_response_body) do
    {
      'errorCode' => '0',
      'response' => { 'oauthCode' => 'OAUTH_CODE_123' }
    }
  end

  let(:login_response) do
    instance_double(Net::HTTPResponse, body: login_response_body.to_json)
  end

  let(:token_body) do
    { 'accessToken' => 'ACCESS_TOKEN', 'refreshToken' => 'REFRESH_TOKEN' }
  end

  before do
    allow(Spl::UrlCreatorService).to receive(:new)
      .with('https://spl.test')
      .and_return(double(login: login_url.to_s))

    allow(Spl::StorePrivateMetadataService).to receive(:all)
      .with(store)
      .and_return(env)

    allow(Spl::SendRequestService).to receive(:new)
      .and_return(send_request_service)

    allow(send_request_service).to receive(:call).and_return(login_response)

    allow(Spl::OauthTokenService).to receive(:new)
      .and_return(oauth_service)

    allow(oauth_service).to receive(:authorization_code_token)
      .with('OAUTH_CODE_123')
      .and_return(token_body)
  end

  describe '#call' do
    context 'when SPL login succeeds' do
      it 'updates user tokens from oauth token service' do
        service.call

        user.reload
        expect(user.private_metadata['spl_access_token']).to eq('ACCESS_TOKEN')
        expect(user.private_metadata['spl_refresh_token']).to eq('REFRESH_TOKEN')
      end

      it 'sends request to login URL with expected body (hashed OTP when length is 6)' do
        expected_password = Digest::SHA256.hexdigest(otp_code)

        expect(Spl::SendRequestService).to receive(:new) do |url, body|
          expect(url).to eq(login_url)
          expect(body).to include(
            apiUser: 'user',
            scope: ['spl_cwp'],
            responseType: 'code',
            method: 'OTP'
          )
          expect(body[:context]).to eq(prgCode: 'PRG')
          expect(body[:password]).to eq(expected_password)
          expect(body[:login]).to eq(phone)

          send_request_service
        end

        service.call
      end
    end

    context 'when SPL returns an error' do
      let(:login_response_body) do
        { 'errorCode' => '123', 'msg' => 'Bad OTP' }
      end

      it 'raises SplLoginAccountError' do
        expect { service.call }
          .to raise_error(Spl::LoginAccountService::SplLoginAccountError)
      end

      it 'does not update user tokens' do
        expect do
          service.call
        rescue StandardError
          nil
        end.not_to(change { user.reload.private_metadata })
      end
    end

    context 'when OTP code is not 6 characters' do
      let(:otp_code) { 'ALREADY_ENCRYPTED_OR_LONGER' }

      it 'uses OTP as-is (no hashing)' do
        expect(Spl::SendRequestService).to receive(:new) do |_url, body|
          expect(body[:password]).to eq(otp_code)
          send_request_service
        end

        service.call
      end
    end

    context 'when card number is provided and phone is nil' do
      let(:phone) { nil }
      let(:card_number) { '1234567890123' }

      it 'uses card number as login' do
        expect(Spl::SendRequestService).to receive(:new) do |_url, body|
          expect(body[:login]).to eq(card_number)
          send_request_service
        end

        service.call
      end
    end

    context 'when raw_otp option is true' do
      subject(:service) { described_class.new(user, store, params, raw_otp: true) }

      it 'uses OTP as-is without hashing even if length is 6' do
        expect(Spl::SendRequestService).to receive(:new) do |_url, body|
          expect(body[:password]).to eq(otp_code)
          send_request_service
        end

        service.call
      end
    end

    context 'when both card number and phone number are present' do
      let(:card_number) { '1234567890123' }

      it 'prioritizes card number over phone number' do
        expect(Spl::SendRequestService).to receive(:new) do |_url, body|
          expect(body[:login]).to eq(card_number)
          send_request_service
        end

        service.call
      end
    end
  end
end
