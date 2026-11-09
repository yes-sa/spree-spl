# frozen_string_literal: true

Spree::Core::Engine.add_routes do
  namespace :api, defaults: { format: 'json' } do
    if ::Spree.version.to_f >= 5.4
      # Spree 5.4+ API v3 routes
      namespace :v3 do
        namespace :store do
          resources :carts, only: [] do
            member do
              patch :update_spl_card_activate
            end
          end
          resource :customer, only: [] do
            patch :login_code
            patch :registration_code
            post :connect_loyalty_account
            post :register_loyalty_account
          end
        end
      end
    else
      # Spree 4.x / 5.0-5.3 API v2 routes
      namespace :v2 do
        namespace :storefront do
          resource :cart, controller: :cart, only: %i[show create destroy] do
            patch :update_spl_card_activate, to: 'cart#update_spl_card_activate'
          end
          resource :account, controller: :account, only: %i[show create update] do
            patch :login_code, to: 'account#login_code'
            patch :registration_code, to: 'account#registration_code'
            post :connect_loyalty_account, to: 'account#connect_loyalty_account'
            post :register_loyalty_account, to: 'account#register_loyalty_account'
          end
        end
      end
    end
  end

  resource :checkout, as: 'coupons', controller: :checkout, only: %i[show create update] do
    post :activate_coupon, to: 'checkout#activate_coupon'
    post :deactivate_coupon, to: 'checkout#deactivate_coupon'
    post :apply_discount_code, to: 'checkout#apply_discount_code'
    delete :remove_discount_code, to: 'checkout#remove_discount_code'
  end
  namespace :account do
    resource :profile, controller: :profile, only: [:edit, :update] do
      patch :registration_code
      post :register_loyalty_account
      patch :login_code
      post :connect_loyalty_account
    end
  end
end
