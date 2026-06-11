# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::Account::ProfileController, type: :controller do
  before do
    stub_const('Spl::SendOtpService::SplSendOtpError', Class.new(StandardError)) unless defined?(Spl::SendOtpService::SplSendOtpError)
  end

  let(:country) { create(:country) }
  let(:store) { create(:store, default_country: country) }
  let!(:user) { create(:user, public_metadata: {}) }

  let(:terms_accepted) { 'true' }
  let(:phone_valid) { true }
  let(:phone_value) { '+48500600700' }

  let(:phone_double) do
    instance_double(
      'PhoneParserService',
      valid?: phone_valid,
      country_code: '+48',
      national_number: '500600700',
      e164: '+48500600700'
    )
  end

  let(:turbo_stream_helper) { instance_double('TurboStreamHelper') }

  before do
    allow(controller).to receive(:current_store).and_return(store)
    allow(controller).to receive(:try_spree_current_user).and_return(user)
    allow(controller).to receive(:login_code_params).and_return(
      ActionController::Parameters.new(phone: phone_value, accept_yc_terms: terms_accepted).permit!
    )
    allow(controller).to receive(:phone_parser).and_return(phone_double)
    allow(controller).to receive(:turbo_stream).and_return(turbo_stream_helper)
    allow(turbo_stream_helper).to receive(:replace).and_return('<turbo-stream></turbo-stream>')
    allow(Spree::Spl).to receive(:report_error).and_return(nil)
    user.errors.clear
  end

  describe '#validate_login_code_request (before_action logic)' do
    context 'when YC terms are not accepted' do
      let(:terms_accepted) { 'false' }

      it 'adds error and renders 422 (does not touch OTP service)' do
        expect(Spl::SendOtpService).not_to receive(:new)
        expect(controller).to receive(:render).with(hash_including(status: :unprocessable_content))
        controller.send(:validate_login_code_request)
        expect(user.errors.full_messages.join(' ')).to include(I18n.t('spl.user.errors.must_accept_yc_terms'))
      end
    end

    context 'when phone is invalid' do
      let(:phone_valid) { false }

      it 'adds phone error and renders 422 (does not touch OTP service)' do
        expect(Spl::SendOtpService).not_to receive(:new)
        expect(controller).to receive(:render).with(hash_including(status: :unprocessable_content))
        controller.send(:validate_login_code_request)
        expect(user.errors.full_messages.join(' ')).to include(I18n.t('spl.user.errors.invalid_phone'))
      end
    end

    context 'when everything is valid' do
      it 'does not render and does not add errors' do
        expect(controller).not_to receive(:render)
        controller.send(:validate_login_code_request)
        expect(user.errors).to be_empty
      end
    end
  end

  describe '#login_code (service + success/rescue)' do
    context 'when OTP service raises SplSendOtpError' do
      it 'renders 422 and shows translated message as base error' do
        service_instance = instance_double('Spl::SendOtpService')

        payload = {
          'errorCode' => 'TEMPORARY_BLOCKED',
          'validationMessages' => nil,
          'fieldValidationMessages' => nil,
          'response' => nil,
          'msg' => 'Temporarily blocked (too much attempts)'
        }

        expect(Spl::SendOtpService).to receive(:new)
          .with(kind_of(DateTime), '+48', '500600700', store)
          .and_return(service_instance)

        expect(service_instance).to receive(:call).and_raise(Spl::SendOtpService::SplSendOtpError.new(payload.inspect))

        expect(controller).to receive(:render).with(hash_including(status: :unprocessable_content))

        controller.login_code

        expect(user.errors.full_messages.join(' '))
          .to include(I18n.t('spl.errors.temporary_blocked'))
      end
    end

    context 'when OTP is sent successfully' do
      it 'calls OTP service, updates accept_yc_terms in public_metadata, and renders 200' do
        service_instance = instance_double('Spl::SendOtpService')

        expect(Spl::SendOtpService).to receive(:new)
          .with(kind_of(DateTime), '+48', '500600700', store)
          .and_return(service_instance)
        expect(service_instance).to receive(:call)
        expect(controller).to receive(:render).with(hash_including(status: :ok))
        controller.login_code
        expect(user.reload.public_metadata['accept_yc_terms']).to eq(true)
      end
    end
  end

  describe '#connect_loyalty_account (service + success/rescue)' do
    let(:service_params) { { user: { spl_auth_code: '123456' } } }

    before do
      allow(controller).to receive(:params).and_return(service_params)
    end

    context 'when account is connected successfully' do
      it 'calls LoginAccountService and AssignSpartaCardNumberService, then redirects with notice' do
        login_service  = instance_double(Spl::LoginAccountService)
        assign_service = instance_double(AssignSpartaCardNumberService)

        expect(Spl::LoginAccountService).to receive(:new)
          .with(user, store, service_params)
          .and_return(login_service)
        expect(login_service).to receive(:call)

        expect(AssignSpartaCardNumberService).to receive(:new)
          .with(user, store)
          .and_return(assign_service)
        expect(assign_service).to receive(:call)

        expect(controller).to receive(:redirect_to).with(
          spree.edit_account_profile_path,
          hash_including(notice: Spree.t(:successfully_updated, resource: Spree.t(:account)))
        )

        controller.connect_loyalty_account
      end
    end

    shared_examples 'renders connect error' do |error_class|
      it "renders 422 and adds translated base error for #{error_class}" do
        payload = {
          'errorCode' => 'TEMPORARY_BLOCKED',
          'validationMessages' => nil,
          'fieldValidationMessages' => nil,
          'response' => nil,
          'msg' => 'Temporarily blocked (too much attempts)'
        }

        phone_obj = double('Phone', e164: '+48500600700')
        allow(user).to receive(:phone).and_return(phone_obj)

        login_service = instance_double(Spl::LoginAccountService)
        allow(Spl::LoginAccountService).to receive(:new).and_return(login_service)
        allow(login_service).to receive(:call)
          .and_raise(error_class.new(payload.inspect))

        expect(controller).to receive(:render).with(hash_including(status: :unprocessable_content))

        controller.connect_loyalty_account

        expect(user.errors.full_messages.join(' '))
          .to include(I18n.t('spl.errors.temporary_blocked'))
      end
    end

    context 'when LoginAccountService raises' do
      include_examples 'renders connect error', Spl::LoginAccountService::SplLoginAccountError
    end

    context 'when AssignSpartaCardNumberService raises' do
      include_examples 'renders connect error', AssignSpartaCardNumberService::AssignSpartaCardNumberError
    end

    context 'when MeService raises' do
      include_examples 'renders connect error', Spl::MeService::SplMeError
    end
  end

  describe '#registration_code (service + success/rescue)' do
    before do
      allow(controller).to receive(:params).and_return(
        ActionController::Parameters.new(user: { phone: phone_value, accept_yc_terms: terms_accepted })
      )
    end

    context 'when OTP request succeeds' do
      it 'calls RequestOtpService, updates user, and renders 200' do
        service_instance = instance_double(Spl::RequestOtpService)

        expect(Spl::RequestOtpService).to receive(:new) do |date, passed_store, passed_params|
          expect(date).to be_a(DateTime)
          expect(passed_store).to eq(store)
          expect(passed_params['mobile_country']).to eq('+48')
          expect(passed_params['phone_number']).to eq('500600700')
        end.and_return(service_instance)

        expect(service_instance).to receive(:call)
        expect(controller).to receive(:render).with(hash_including(status: :ok))

        controller.registration_code

        expect(user.reload.phone).to eq(phone_value)
        expect(user.public_metadata['accept_yc_terms']).to eq(true)
      end
    end

    shared_examples 'registration_code error' do |error_class|
      it "renders 422 and adds translated base error for #{error_class}" do
        payload = {
          'errorCode' => 'TEMPORARY_BLOCKED',
          'msg' => 'Temporarily blocked'
        }

        service_instance = instance_double(Spl::RequestOtpService)

        allow(Spl::RequestOtpService).to receive(:new).and_return(service_instance)
        allow(service_instance).to receive(:call).and_raise(error_class.new(payload.inspect))

        expect(controller).to receive(:render).with(hash_including(status: :unprocessable_content))

        controller.registration_code

        expect(user.errors.full_messages.join(' ')).to include(I18n.t('spl.errors.temporary_blocked'))
      end
    end

    context 'when RequestOtpService raises error' do
      include_examples 'registration_code error', Spl::RequestOtpService::SplRequestOtpError
    end

    context 'when OauthTokenService raises error' do
      include_examples 'registration_code error', Spl::OauthTokenService::OauthTokenError
    end
  end

  describe '#register_loyalty_account (service + success/rescue)' do
    let(:params_hash) { { 'user' => { 'spl_auth_code' => '123456' } } }

    before do
      allow(controller).to receive(:params).and_return(params_hash)
      allow(controller).to receive(:spree_current_user).and_return(user)
    end

    context 'when registration succeeds but session upgrade fails (no access token)' do
      it 'sends a login OTP and renders otp_code_form as fallback' do
        service_instance = instance_double(Spl::RegisterAccountService)
        otp_service = instance_double('Spl::SendOtpService')

        allow(Spl::RegisterAccountService).to receive(:new)
          .with(user, store, '123456')
          .and_return(service_instance)
        allow(service_instance).to receive(:call)

        # Simulate no session upgrade (no access token in private_metadata)
        allow(user).to receive(:private_metadata).and_return({})

        phone_obj = instance_double(PhoneParserService, country_code: '+48', national_number: '500600700', e164: '+48500600700')
        allow(PhoneParserService).to receive(:new).with(user.phone).and_return(phone_obj)

        expect(Spl::SendOtpService).to receive(:new)
          .with(kind_of(DateTime), '+48', '500600700', store)
          .and_return(otp_service)
        expect(otp_service).to receive(:call)

        expect(controller).to receive(:render).with(hash_including(status: :unprocessable_content))

        controller.register_loyalty_account

        expect(user.errors.full_messages.join(' '))
          .to include('Rejestracja zakończona pomyślnie')
      end
    end

    context 'when PERSON_EMAIL_ALREADY_EXISTS and auto-connect succeeds' do
      it 'logs in with existing OTP and redirects' do
        service_instance = instance_double(Spl::RegisterAccountService)
        login_service = instance_double(Spl::LoginAccountService)
        assign_service = instance_double(AssignSpartaCardNumberService)

        payload = {
          'errorCode' => 'PERSON_EMAIL_ALREADY_EXISTS',
          'msg' => 'Customer with this email is already registered'
        }

        allow(Spl::RegisterAccountService).to receive(:new).and_return(service_instance)
        allow(service_instance).to receive(:call)
          .and_raise(Spl::RegisterAccountService::SplRegisterAccountError.new(payload.inspect))

        expect(Spl::LoginAccountService).to receive(:new)
          .with(user, store, params_hash)
          .and_return(login_service)
        expect(login_service).to receive(:call)

        expect(AssignSpartaCardNumberService).to receive(:new)
          .with(user, store)
          .and_return(assign_service)
        expect(assign_service).to receive(:call)

        expect(controller).to receive(:redirect_to).with(
          spree.edit_account_profile_path,
          hash_including(notice: Spree.t(:successfully_updated, resource: Spree.t(:account)))
        )

        controller.register_loyalty_account
      end
    end

    context 'when PERSON_EMAIL_ALREADY_EXISTS and auto-connect fails' do
      it 'sends a fresh SMS and renders otp_code_form' do
        service_instance = instance_double(Spl::RegisterAccountService)
        login_service = instance_double(Spl::LoginAccountService)
        otp_service = instance_double('Spl::SendOtpService')

        payload = {
          'errorCode' => 'PERSON_EMAIL_ALREADY_EXISTS',
          'msg' => 'Customer with this email is already registered'
        }

        allow(Spl::RegisterAccountService).to receive(:new).and_return(service_instance)
        allow(service_instance).to receive(:call)
          .and_raise(Spl::RegisterAccountService::SplRegisterAccountError.new(payload.inspect))

        allow(Spl::LoginAccountService).to receive(:new).and_return(login_service)
        allow(login_service).to receive(:call)
          .and_raise(Spl::LoginAccountService::SplLoginAccountError.new('AUTH_FAILED'))

        phone_obj = instance_double(PhoneParserService, country_code: '+48', national_number: '500600700', e164: '+48500600700')
        allow(PhoneParserService).to receive(:new).with(user.phone).and_return(phone_obj)

        expect(Spl::SendOtpService).to receive(:new)
          .with(kind_of(DateTime), '+48', '500600700', store)
          .and_return(otp_service)
        expect(otp_service).to receive(:call)

        expect(controller).to receive(:render).with(hash_including(status: :unprocessable_content))

        controller.register_loyalty_account

        expect(user.errors.full_messages.join(' '))
          .to include(I18n.t('spl.errors.person_email_already_exists_sms', email: user.email))
      end
    end

    context 'when PERSON_EMAIL_ALREADY_EXISTS and SendOtpService is rate-limited' do
      it 'renders the rate-limit error without crashing' do
        service_instance = instance_double(Spl::RegisterAccountService)
        login_service = instance_double(Spl::LoginAccountService)
        otp_service = instance_double('Spl::SendOtpService')

        reg_payload = {
          'errorCode' => 'PERSON_EMAIL_ALREADY_EXISTS',
          'msg' => 'Customer with this email is already registered'
        }

        blocked_payload = {
          'errorCode' => 'TEMPORARY_BLOCKED',
          'msg' => 'Temporarily blocked (too much attempts)'
        }

        allow(Spl::RegisterAccountService).to receive(:new).and_return(service_instance)
        allow(service_instance).to receive(:call)
          .and_raise(Spl::RegisterAccountService::SplRegisterAccountError.new(reg_payload.inspect))

        allow(Spl::LoginAccountService).to receive(:new).and_return(login_service)
        allow(login_service).to receive(:call)
          .and_raise(Spl::LoginAccountService::SplLoginAccountError.new('AUTH_FAILED'))

        phone_obj = instance_double(PhoneParserService, country_code: '+48', national_number: '500600700', e164: '+48500600700')
        allow(PhoneParserService).to receive(:new).with(user.phone).and_return(phone_obj)

        allow(Spl::SendOtpService).to receive(:new).and_return(otp_service)
        allow(otp_service).to receive(:call)
          .and_raise(Spl::SendOtpService::SplSendOtpError.new(blocked_payload.inspect))

        expect(controller).to receive(:render).with(hash_including(status: :unprocessable_content))

        controller.register_loyalty_account

        expect(user.errors.full_messages.join(' '))
          .to include(I18n.t('spl.errors.temporary_blocked'))
      end
    end

    shared_examples 'register_loyalty_account error' do |error_class|
      it "renders 422 and adds translated base error for #{error_class}" do
        payload = {
          'errorCode' => 'TEMPORARY_BLOCKED',
          'msg' => 'Temporarily blocked'
        }

        phone_obj = double('Phone', e164: '+48500600700')
        allow(user).to receive(:phone).and_return(phone_obj)

        service_instance = instance_double(Spl::RegisterAccountService)

        allow(Spl::RegisterAccountService).to receive(:new).and_return(service_instance)
        allow(service_instance).to receive(:call).and_raise(error_class.new(payload.inspect))

        expect(controller).to receive(:render).with(hash_including(status: :unprocessable_content))

        controller.register_loyalty_account

        expect(user.errors.full_messages.join(' ')).to include(I18n.t('spl.errors.temporary_blocked'))
      end
    end

    context 'when RegisterAccountService raises error' do
      include_examples 'register_loyalty_account error', Spl::RegisterAccountService::SplRegisterAccountError
    end

    context 'when OauthTokenService raises error' do
      include_examples 'register_loyalty_account error', Spl::OauthTokenService::OauthTokenError
    end
  end

  describe '#connect_loyalty_account with redirect_to param' do
    let(:service_params) { { user: { spl_auth_code: '123456' }, redirect_to: 'http://localhost:3000/cart' } }

    before do
      allow(controller).to receive(:params).and_return(service_params)
    end

    it 'redirects to redirect_to param instead of profile path' do
      login_service  = instance_double(Spl::LoginAccountService)
      assign_service = instance_double(AssignSpartaCardNumberService)

      allow(Spl::LoginAccountService).to receive(:new).and_return(login_service)
      allow(login_service).to receive(:call)

      allow(AssignSpartaCardNumberService).to receive(:new).and_return(assign_service)
      allow(assign_service).to receive(:call)

      expect(controller).to receive(:redirect_to).with(
        'http://localhost:3000/cart',
        hash_including(notice: Spree.t(:successfully_updated, resource: Spree.t(:account)))
      )

      controller.connect_loyalty_account
    end
  end
end
