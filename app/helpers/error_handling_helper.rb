# frozen_string_literal: true

module ErrorHandlingHelper
  # Parses and translate occurred error, then adds it to user errors.
  # Dedicated for storefront controllers.
  # @param [StandardError]
  def handle_spl_error(error, model)
    payload = Spl::ErrorPayloadParser.parse(error.message) || error
    msg = Spl::ErrorTranslator.translate(payload)

    return unless model
    
    clear_errors(model)
    model.errors.add(:base, msg)
  end

  def clear_errors(model)
    model.errors.clear
  end

  def token_expired?(err_msg)
    err_msg == 'TOKEN_EXPIRED'
  end
end
