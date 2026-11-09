# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spl::MeService, type: :service do
  subject(:service) { described_class.new(user, store) }

  let(:country) { create(:country) }
  let(:user) { create(:user, private_metadata: { 'spl_access_token' => 'access-token-123' }) }
  let(:store) { create(:store, default_country: country, private_metadata: { 'spl_url' => 'https://api.example.test' }) }
  let(:env) { { 'spl_prg_code' => 'PRG001' } }
  let(:me_url) { 'https://api.example.test/me' }

  before do
    allow(Spl::StorePrivateMetadataService).to receive(:all).with(store).and_return(env)

    url_creator = instance_double(Spl::UrlCreatorService, me: me_url)
    allow(Spl::UrlCreatorService).to receive(:new).with('https://api.example.test').and_return(url_creator)
  end

  describe '#call' do
    context "when API returns success (errorCode == '0')" do
      let(:expected_body) do
        {
          context: {
            prgCode: 'PRG001',
            oauthToken: 'access-token-123'
          }
        }
      end
      let(:success_response_hash) do
        {
          'errorCode' => '0',
          'validationMessages' => nil,
          'fieldValidationMessages' => nil,
          'response' => {
            'person' => {
              'addonsList' => [],
              'address' => {},
              'addresses' => nil,
              'assignedPlace' => {
                'id' => 'id123',
                'idAsDictLabel' => 'shop.pl'
              },
              'assignedPlaceManualId' => nil,
              'avatarUrl' => nil,
              'birthDate' => nil,
              'cards' => [
                {
                  'burnEnabled' => true,
                  'cardType' => {
                    'id' => 'id234',
                    'idAsDictLabel' => 'Shop - Default Virtual Card'
                  },
                  'depositBurnDisabled' => nil,
                  'no' => '5100179585157',
                  'status' => 'A',
                  'statusAsDictLabel' => 'Active'
                }
              ],
              'company' => nil,
              'email' => 'name.surname@email.com',
              'emailVerified' => nil,
              'firstName' => 'name',
              'gender' => nil,
              'lastName' => 'surname',
              'marital' => nil,
              'middleName' => nil,
              'mobile' => '500600700',
              'mobileCountry' => '+48',
              'mobileVerified' => true,
              'nameDay' => nil,
              'passwordLastChanged' => nil,
              'permissions' => {},
              'personId' => 'id345',
              'phone' => nil,
              'preReg' => nil,
              'preferredCommChannel' => nil,
              'pushNotificationsEnabled' => nil,
              'social' => [],
              'taxNo' => nil,
              'undefined' => false,
              'walletOwner' => true,
              'maritalAsDictLabel' => nil
            },
            'cards' => [
              {
                'burnEnabled' => true,
                'cardType' => {
                  'id' => 'id456',
                  'idAsDictLabel' => 'Shop - Default Virtual Card'
                },
                'depositBurnDisabled' => nil,
                'no' => '5100179585157',
                'status' => 'A',
                'statusAsDictLabel' => 'Active'
              }
            ],
            'wallet' => {
              'balances' => [
                {
                  'balance' => 0.0,
                  'nbBalance' => 0.0,
                  'type' => 'P',
                  'typeAsDictLabel' => 'Points'
                }
              ],
              'primaryBalance' => 0.0,
              'toBeExpired' => { 'primaryBalance' => {} },
              'firstTx' => { 'date' => nil }
            },
            'badges' => [],
            'mainCard' => {
              'burnEnabled' => true,
              'cardType' => {
                'id' => 'id567',
                'idAsDictLabel' => 'Shop - Default Virtual Card'
              },
              'depositBurnDisabled' => nil,
              'no' => '5100179585157',
              'status' => 'A',
              'statusAsDictLabel' => 'Active'
            },
            'forcePasswordChange' => false
          },
          'msg' => 'OK'
        }
      end

      it 'sends request with correct body and returns parsed response body' do
        response = double('Response', body: success_response_hash.to_json)
        request_service = instance_double(Spl::SendRequestService)

        expect(Spl::SendRequestService).to receive(:new)
          .with(URI.parse(me_url), expected_body)
          .and_return(request_service)
        expect(request_service).to receive(:call).and_return(response)
        expect(service.call).to eq(success_response_hash)
      end
    end

    context "when API returns an error (errorCode != '0')" do
      let(:error_response_hash) do
        {
          'errorCode' => 'TEMPORARY_BLOCKED',
          'msg' => 'Temporarily blocked'
        }
      end

      before do
        response = double('Response', body: error_response_hash.to_json)
        request_service = instance_double(Spl::SendRequestService)
        allow(Spl::SendRequestService).to receive(:new).and_return(request_service)
        allow(request_service).to receive(:call).and_return(response)
      end

      it 'raises SplMeError' do
        expect { service.call }
          .to raise_error(Spl::MeService::SplMeError, error_response_hash.to_s)
      end
    end

    context 'when the access token has expired' do
      let(:user) do
        create(:user, private_metadata: {
                 'spl_access_token' => 'expired-access-token',
                 'spl_refresh_token' => 'refresh-token-123',
                 'unrelated_key' => 'preserved-value'
               })
      end
      let(:expired_response) do
        { 'errorCode' => 'TOKEN_EXPIRED', 'msg' => 'Token expired' }
      end
      let(:success_response) do
        { 'errorCode' => '0', 'response' => { 'person' => {} }, 'msg' => 'OK' }
      end
      let(:oauth_service) { instance_double(Spl::OauthTokenService) }

      before do
        responses = [
          double('Response', body: expired_response.to_json),
          double('Response', body: success_response.to_json)
        ]
        request_service = instance_double(Spl::SendRequestService)

        allow(Spl::SendRequestService).to receive(:new).and_return(request_service)
        allow(request_service).to receive(:call).and_return(*responses)
        allow(Spl::OauthTokenService).to receive(:new).with(kind_of(DateTime), store).and_return(oauth_service)
        allow(oauth_service).to receive(:refresh_token).with('refresh-token-123').and_return(
          'accessToken' => 'refreshed-access-token',
          'refreshToken' => 'refreshed-refresh-token'
        )
      end

      it 'refreshes the tokens, preserves metadata and retries the request' do
        expect(service.call).to eq(success_response)
        expect(user.reload.private_metadata).to include(
          'spl_access_token' => 'refreshed-access-token',
          'spl_refresh_token' => 'refreshed-refresh-token',
          'unrelated_key' => 'preserved-value'
        )
        expect(Spl::SendRequestService).to have_received(:new).with(
          URI.parse(me_url),
          context: { prgCode: 'PRG001', oauthToken: 'refreshed-access-token' }
        )
      end
    end
  end
end
