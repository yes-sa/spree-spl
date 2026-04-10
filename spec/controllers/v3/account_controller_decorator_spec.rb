# frozen_string_literal: true

require 'rails_helper'

return unless defined?(Spree::Api::V3::Store::CustomersController)

RSpec.describe Spree::Api::V3::Store::CustomersController, type: :controller do
  let(:store) { Spree::Store.default || create(:store, default: true) }
  let(:user)  { create(:user) }

  before do
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:current_store).and_return(store)
    allow(controller).to receive(:authenticate_user).and_return(true)
    allow(controller).to receive(:authenticate_api_key!).and_return(true)
  end

  describe 'POST #connect_loyalty_account' do
    let(:params) do
      {
        'user' => {
          'public_metadata' => {
            'mobile_country' => '+48',
            'phone_number' => '123345125',
            'card_number' => '0123456789123',
            'spl_auth_code' => 'BVSMWX8YYTH98SZAVHYEZJZC7PYPKS'
          }
        }
      }
    end

    context 'when successful' do
      before do
        allow(controller).to receive(:assign_card_number)
          .with(user, store, kind_of(ActionController::Parameters))
          .and_return(true)
      end

      it 'authorizes the action' do
        expect(controller).to receive(:authorize!).with(:update, user)

        post :connect_loyalty_account,
             params: params,
             format: :json
      end

      it 'reloads the user and returns serialized payload' do
        expect(user).to receive(:reload)

        post :connect_loyalty_account,
             params: params,
             format: :json

        expect(response).to have_http_status(:ok)

        json = response.parsed_body
        expect(json).to have_key('id')
      end
    end

    context 'when AssignSpartaCardNumberService raises an exception' do
      before do
        allow(controller).to receive(:assign_card_number).and_raise(
          AssignSpartaCardNumberService::AssignSpartaCardNumberError.new('Assigning failed')
        )
      end

      it 'returns bad_request with error JSON' do
        post :connect_loyalty_account,
             params: params,
             format: :json

        expect(response).to have_http_status(:bad_request)

        json = response.parsed_body
        expect(json['error'].to_s).to include('Assigning failed')
      end
    end

    context 'when SplLoginAccountError is raised' do
      before do
        allow(controller).to receive(:assign_card_number).and_raise(
          Spl::LoginAccountService::SplLoginAccountError.new('Login failed')
        )
      end

      it 'returns bad_request with error JSON' do
        post :connect_loyalty_account,
             params: params,
             format: :json

        expect(response).to have_http_status(:bad_request)

        json = response.parsed_body
        expect(json['error'].to_s).to include('Login failed')
      end
    end
  end

  describe 'POST #register_loyalty_account' do
    let(:params) do
      {
        'user' => {
          'public_metadata' => {
            'mobile_country' => '+48',
            'phone_number' => '123345125',
            'splAuthCode' => 'BVSMWX8YYTH98SZAVHYEZJZC7PYPKS',
            'splProcessData' => 'true',
            'operationalSms' => 'true'
          }
        }
      }
    end

    let(:service_instance) do
      instance_double(Spl::RegisterAccountService)
    end

    before do
      allow(controller).to receive(:current_user).and_return(user)
      allow(controller).to receive(:current_store).and_return(store)

      allow(Spl::RegisterAccountService)
        .to receive(:new)
        .with(user, store, kind_of(ActionController::Parameters))
        .and_return(service_instance)
    end

    context 'when successful' do
      before do
        allow(service_instance).to receive(:call).and_return(true)
      end

      it 'authorizes the user' do
        expect(controller).to receive(:authorize!).with(:update, user)

        post :register_loyalty_account, params: params, format: :json
      end

      it 'calls the RegisterAccountService' do
        expect(service_instance).to receive(:call)

        post :register_loyalty_account, params: params, format: :json
      end

      it 'reloads the user and returns serialized payload' do
        expect(user).to receive(:reload)

        post :register_loyalty_account, params: params, format: :json

        expect(response).to have_http_status(:ok)

        json = response.parsed_body
        expect(json).to have_key('id')
      end
    end

    context 'when SplRegisterAccountError is raised' do
      before do
        allow(service_instance).to receive(:call)
          .and_raise(Spl::RegisterAccountService::SplRegisterAccountError.new('Register failed'))
      end

      it 'returns bad_request with error JSON' do
        post :register_loyalty_account, params: params, format: :json

        expect(response).to have_http_status(:bad_request)

        json = response.parsed_body
        expect(json['error'].to_s).to include('Register failed')
      end
    end

    context 'when OauthTokenError is raised' do
      before do
        allow(service_instance).to receive(:call)
          .and_raise(Spl::OauthTokenService::OauthTokenError.new('Token invalid'))
      end

      it 'returns bad_request with error JSON' do
        post :register_loyalty_account, params: params, format: :json

        expect(response).to have_http_status(:bad_request)

        json = response.parsed_body
        expect(json['error'].to_s).to include('Token invalid')
      end
    end
  end

  describe 'PATCH #registration_code' do
    let(:params) { { phone_number: '123345125', mobile_country: '+48', email: 'real_user@example.com' } }

    let(:service_instance) { instance_double(Spl::RequestOtpService) }

    before do
      allow(controller).to receive(:current_store).and_return(store)

      allow(Spl::RequestOtpService)
        .to receive(:new)
        .with(instance_of(DateTime), store, kind_of(ActionController::Parameters))
        .and_return(service_instance)
    end

    context 'when OTP request succeeds' do
      before do
        allow(service_instance).to receive(:call).and_return(true)
      end

      it 'calls the service and returns 204 No Content' do
        patch :registration_code, params: params, format: :json

        expect(service_instance).to have_received(:call)
        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_blank
      end
    end

    context 'when SplRequestOtpError is raised' do
      before do
        allow(service_instance).to receive(:call)
          .and_raise(Spl::RequestOtpService::SplRequestOtpError.new('OTP failed'))
      end

      it 'returns 400 Bad Request with error JSON' do
        patch :registration_code, params: params, format: :json

        expect(response).to have_http_status(:bad_request)

        json = response.parsed_body
        expect(json['error'].to_s).to include('OTP failed')
      end
    end

    context 'when OauthTokenError is raised' do
      before do
        allow(service_instance).to receive(:call)
          .and_raise(Spl::OauthTokenService::OauthTokenError.new('Token invalid'))
      end

      it 'returns 400 Bad Request with error JSON' do
        patch :registration_code, params: params, format: :json

        expect(response).to have_http_status(:bad_request)

        json = response.parsed_body
        expect(json['error'].to_s).to include('Token invalid')
      end
    end
  end

  describe 'PATCH #login_code' do
    let(:params) do
      {
        mobile_country: '+48',
        phone_number: '123345125'
      }
    end

    let(:service_instance) { instance_double(Spl::SendOtpService) }

    before do
      allow(controller).to receive(:current_user).and_return(user)
      allow(controller).to receive(:current_store).and_return(store)

      allow(Spl::SendOtpService)
        .to receive(:new)
        .with(
          instance_of(DateTime),
          '+48',
          '123345125',
          store
        )
        .and_return(service_instance)
    end

    context 'when authorization passes' do
      before do
        allow(controller).to receive(:authorize!)
          .with(:update, user)
          .and_return(true)

        allow(service_instance).to receive(:call).and_return(true)
      end

      it 'calls the service and returns 204 No Content' do
        patch :login_code, params: params, format: :json

        expect(service_instance).to have_received(:call)
        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_blank
      end
    end

    context 'when authorization fails' do
      before do
        allow(controller).to receive(:authorize!)
          .with(:update, user)
          .and_raise(CanCan::AccessDenied.new('Not allowed'))
      end

      it 'returns 403 Forbidden' do
        patch :login_code, params: params, format: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when SplSendOtpError is raised' do
      before do
        allow(controller).to receive(:authorize!).and_return(true)
        allow(service_instance).to receive(:call)
          .and_raise(Spl::SendOtpService::SplSendOtpError.new('OTP sending failed'))
      end

      it 'returns 400 Bad Request with error JSON' do
        patch :login_code, params: params, format: :json

        expect(response).to have_http_status(:bad_request)

        json = response.parsed_body
        expect(json['error'].to_s).to include('OTP sending failed')
      end
    end
  end

  describe 'validate_spl_no_card before_action on #update' do
    before do
      allow(controller).to receive(:current_store).and_return(store)
    end
    let(:service) { instance_double(Spl::ValidateCardService, call: true) }

    it 'does nothing when metadata is missing' do
      expect(Spl::ValidateCardService).not_to receive(:new)

      patch :update, params: { metadata: {} }, as: :json
      expect(response).not_to have_http_status(:bad_request)
    end

    it 'does nothing when card is being disactivated (spl_card_active present and false)' do
      expect(Spl::ValidateCardService).not_to receive(:new)

      patch :update,
            params: { metadata: { spl_card_active: false, spl_no_card: '0123456789123' } },
            as: :json

      expect(response).not_to have_http_status(:bad_request)
    end

    it 'does nothing when card number is missing' do
      expect(Spl::ValidateCardService).not_to receive(:new)

      patch :update,
            params: { metadata: { spl_card_active: false, spl_no_card: '' } },
            as: :json

      expect(response).not_to have_http_status(:bad_request)
    end

    it 'calls Spl::ValidateCardService when spl_no_card is present and not disactivated' do
      expect(Spl::ValidateCardService)
        .to receive(:new).with('0123456789123', user, store)
                         .and_return(service)
      expect(service).to receive(:call)

      patch :update,
            params: { metadata: { spl_no_card: '0123456789123' } },
            as: :json

      expect(response).to have_http_status(:ok)
    end

    it 'renders 400 and updates the last order when validation fails' do
      order = create(:order, user: user, state: 'cart', public_metadata: {})

      allow(Spl::ValidateCardService).to receive(:new).and_return(service)
      allow(service).to receive(:call).and_raise(
        Spl::ValidateCardService::SplCardValidationError.new('Invalid SPL card')
      )

      patch :update,
            params: { metadata: { spl_no_card: 'BAD' } },
            as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq('error' => 'Invalid SPL card')

      order.reload
      expect(order.public_metadata['spl_no_card']).to be_nil
      expect(order.public_metadata['spl_card_active']).to eq(false)
    end
  end
end
