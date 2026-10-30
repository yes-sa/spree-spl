# frozen_string_literal: true

class AssignSpartaCardNumberService
  class AssignSpartaCardNumberError < StandardError; end

  def initialize(user, store)
    @user = user
    @store = store
  end

  def call
    card_data = customer_info.dig('response', 'mainCard')
    add_card_number_to_user(card_data)
  end

  private

  def customer_info
    Spl::MeService.new(@user, @store).call
  end

  def add_card_number_to_user(card_data)
    if card_data['status'] != 'A'
      raise AssignSpartaCardNumberError, I18n.t('spl.card_validation.errors.card_not_active')
    end
    if card_assigned_to_other_user?(card_data['no'])
      raise AssignSpartaCardNumberError, I18n.t('spl.card_validation.errors.wrong_owner')
    end

    Spl::Metafields.set_card_number(@user, card_data['no'])
    Spl::Metafields.set_card_active(@user, true)
  end

  def card_assigned_to_other_user?(card_number)
    Spl::Metafields.card_assigned_to_other_user?(card_number, @user)
  end
end
