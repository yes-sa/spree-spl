# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spl::Spree::Storefront::CheckoutControllerDecorator, type: :controller do
  controller(ActionController::Base) do
    before_action :set_order

    def checkout_path
      '/checkout'
    end

    def show
      render plain: 'ok'
    end

    def update
      render plain: 'ok'
    end

    # Provided by decorator; defined here so Rails can dispatch

    private

    def set_order
      @order = Spree::Order.first
    end
  end

  before do
    controller.class.prepend described_class
    routes.draw do
      get '/checkout', to: 'anonymous#show'
      patch '/checkout/confirm', to: 'anonymous#update'
      post '/checkout/activate_coupon', to: 'anonymous#activate_coupon'
      post '/checkout/deactivate_coupon', to: 'anonymous#deactivate_coupon'
    end
    allow(request).to receive(:url).and_return('http://test.host/checkout')
  end

  let(:country) { create(:country) }
  let!(:store) { create(:store, default_country: country) }

  let!(:user)  { create(:user) }
  let!(:order) do
    create(:order,
           store: store,
           user: user)
  end

  describe '#promotion_switcher' do
    it 'uses check_only=true before the final confirmation' do
      switcher = instance_double('PromotionSwitcherService', call: true)
      expect(PromotionSwitcherService).to receive(:new).with(order, true).and_return(switcher)

      allow(Spl::Coupons::GetCouponsService)
        .to receive(:new).with(user, store)
                         .and_return(instance_double('Spl::Coupons::GetCouponsService', call: []))

      get :show
      expect(response).to have_http_status(:ok)
    end

    it 'uses check_only=true while rendering the confirmation page' do
      allow_any_instance_of(ActionDispatch::Request)
        .to receive(:url)
        .and_return('http://test.host/checkout/confirm')

      switcher = instance_double('PromotionSwitcherService', call: false)
      expect(PromotionSwitcherService).to receive(:new).with(order, true).and_return(switcher)

      allow(Spl::Coupons::GetCouponsService)
        .to receive(:new).with(user, store)
                         .and_return(instance_double('Spl::Coupons::GetCouponsService', call: []))

      get :show
      expect(response).to have_http_status(:ok)
    end

    it 'uses check_only=false only when the confirmed order is submitted' do
      order.update!(state: 'confirm')
      switcher = instance_double('PromotionSwitcherService', call: true)
      expect(PromotionSwitcherService).to receive(:new).with(order, false).and_return(switcher)

      allow(Spl::Coupons::GetCouponsService)
        .to receive(:new).with(user, store)
                         .and_return(instance_double('Spl::Coupons::GetCouponsService', call: []))

      patch :update, params: { state: 'confirm' }
      expect(response).to have_http_status(:ok)
    end
  end

  describe '#load_user_coupons' do
    it 'loads coupons for user/store and assigns @coupons' do
      allow(PromotionSwitcherService)
        .to receive(:new)
        .and_return(instance_double('PromotionSwitcherService', call: true))

      coupons_service = instance_double('Spl::Coupons::GetCouponsService', call: %w[c1 c2])
      expect(Spl::Coupons::GetCouponsService)
        .to receive(:new).with(user, store).and_return(coupons_service)

      get :show

      expect(response).to have_http_status(:ok)
      expect(assigns(:coupons)).to eq(%w[c1 c2])
    end

    it 'does not run load_user_coupons as a before_action for activate_coupon' do
      allow(PromotionSwitcherService)
        .to receive(:new)
        .and_return(instance_double('PromotionSwitcherService', call: true))

      # This will still be called (inside #activate_coupon), but we can ensure it is not called twice.
      coupons_service = instance_double('Spl::Coupons::GetCouponsService', call: [])
      expect(Spl::Coupons::GetCouponsService).to receive(:new).with(user, store).once.and_return(coupons_service)

      allow(Spl::Coupons::ActivateCouponService)
        .to receive(:new)
        .and_return(instance_double('Spl::Coupons::ActivateCouponService', call: true))

      post :activate_coupon, params: { coupon_code: 'YOLO_90' }, format: :html
    end
  end

  describe '#activate_coupon' do
    let(:activate) { instance_double(Spl::Coupons::ActivateCouponService, call: true) }

    before do
      allow(controller).to receive(:try_spree_current_user).and_return(user)
    end

    context 'when coupon is valid' do
      it 'calls ActivateCouponService, reloads coupons, and redirects (HTML)' do
        expect(Spl::Coupons::ActivateCouponService)
          .to receive(:new).with(user, store, 'YOLO_90').and_return(activate)

        coupons_service = instance_double('Spl::Coupons::GetCouponsService', call: %w[YOLO_90])
        expect(Spl::Coupons::GetCouponsService)
          .to receive(:new).with(user, store).and_return(coupons_service)

        post :activate_coupon, params: { coupon_code: 'YOLO_90' }, format: :html

        expect(assigns(:coupons)).to eq(%w[YOLO_90])
        expect(response).to have_http_status(:found)
        expect(response.location).to include('/checkout')
      end
    end

    context 'when coupon is invalid' do
      it 'still redirects even if ActivateCouponService raises' do
        expect(Spl::Coupons::ActivateCouponService).to receive(:new).with(user, store, 'YOLO_90').and_return(activate)
        expect(activate).to receive(:call).and_raise(Spl::Coupons::ActivateCouponService::ActivateCouponServiceError,
                                                     'some error')

        expect do
          post :activate_coupon, params: { coupon_code: 'YOLO_90' }, format: :html
        end.to raise_error('some error')

        expect(response).to have_http_status(:found)
        expect(response.location).to include('/checkout')
      end
    end
  end

  describe '#deactivate_coupon' do
    before do
      allow(controller).to receive(:try_spree_current_user).and_return(user)
    end

    it 'calls DeactivateCouponService, reloads coupons, and redirects (HTML)' do
      deactivate = instance_double('Spl::Coupons::DeactivateCouponService', call: true)
      expect(Spl::Coupons::DeactivateCouponService)
        .to receive(:new).with(user, store, 'YOLO_90').and_return(deactivate)

      coupons_service = instance_double('Spl::Coupons::GetCouponsService', call: %w[YOLO_90])
      expect(Spl::Coupons::GetCouponsService)
        .to receive(:new).with(user, store).and_return(coupons_service)

      post :deactivate_coupon, params: { coupon_code: 'YOLO_90' }, format: :html

      expect(assigns(:coupons)).to eq(%w[YOLO_90])
      expect(response).to have_http_status(:found)
      expect(response.location).to include('/checkout')
    end

    it 'still redirects even if DeactivateCouponService raises' do
      deactivate = instance_double('Spl::Coupons::DeactivateCouponService')
      expect(Spl::Coupons::DeactivateCouponService).to receive(:new).with(user, store, 'YOLO_90').and_return(deactivate)
      expect(deactivate).to receive(:call).and_raise(
        Spl::Coupons::DeactivateCouponService::DeactivateCouponServiceError, 'some error'
      )

      expect do
        post :deactivate_coupon, params: { coupon_code: 'YOLO_90' }, format: :html
      end.to raise_error('some error')

      expect(response).to have_http_status(:found)
      expect(response.location).to include('/checkout')
    end
  end
end
