# frozen_string_literal: true

Rails.application.config.to_prepare do # rubocop:disable Metrics/BlockLength
  # API controller & serializer decorators — version-dependent
  if ::Spree.version.to_f >= 5.4
    # Spree 5.4+ uses API v3 (Spree::Api::V3::Store::*)
    ::Spree::Api::V3::Store::CartsController.prepend(
      Spl::Spree::Api::V3::CartControllerDecorator
    )

    ::Spree::Api::V3::CartSerializer.prepend(
      V3::CartSerializerDecorator
    )

    ::Spree::Api::V3::Store::CustomersController.prepend(
      Spl::Spree::Api::V3::AccountControllerDecorator
    )
  else
    # Spree 4.x / 5.0–5.3 uses API v2 (Spree::Api::V2::Storefront::*)
    ::Spree::Api::V2::Storefront::CartController.prepend(
      Spl::Spree::Api::CartControllerDecorator
    )

    ::Spree::V2::Storefront::CartSerializer.prepend(
      CartSerializerDecorator
    )

    ::Spree::Api::V2::Storefront::CheckoutController.prepend(
      Spl::Spree::Api::CheckoutControllerDecorator
    )

    ::Spree::Api::V2::Storefront::AccountController.prepend(
      Spl::Spree::Api::AccountControllerDecorator
    )
  end

  # Non-API decorators — shared across all Spree versions
  ::Spree::CheckoutController.prepend(
    Spl::Spree::Storefront::CheckoutControllerDecorator
  )

  ::Spree::Adjustable::AdjustmentsUpdater.prepend(
    Spree::Adjustable::AdjustmentsUpdaterDecorator
  )

  ::Spree::Adjustment.prepend(
    Spree::AdjustmentDecorator
  )

  ::Spree::PromotionHandler::Cart.prepend(
    CartDecorator
  )

  ::Spree::OrderUpdater.prepend(
    OrderUpdaterDecorator
  )

  ::Spree::LineItemsController.prepend(
    Spl::Spree::Storefront::LineItemsControllerDecorator
  )

  ::Spree::Account::ProfileController.prepend(
    Spl::Spree::Storefront::ProfileControllerDecorator
  )

  ::Spree::Admin::PaymentsController.prepend(
    Spl::Spree::Admin::PaymentsControllerDecorator
  )

  ::Spree::CheckoutHelper.prepend(
    CheckoutHelperDecorator
  )

  ::Spree::Promotion::Rules::UserFromClub
  Rails.application.config.spree.promotions.rules << Spree::Promotion::Rules::UserFromClub
end
