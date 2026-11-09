# frozen_string_literal: true

module SplServiceHelper
  def send_request(url, body)
    Spl::SendRequestService.new(url, body).call
  end

  # Refreshes user private token to keep possible
  # using customer oriented endpoints
  # @param [user: Spree::User]
  def refresh_user_token(user, store)
    metadata = user.private_metadata&.stringify_keys
    refresh_token = metadata&.dig('spl_refresh_token')
    return if refresh_token.blank?

    response = Spl::OauthTokenService.new(DateTime.current, store).refresh_token(refresh_token)

    user.update!(private_metadata: metadata.merge(
      'spl_access_token' => response.fetch('accessToken'),
      'spl_refresh_token' => response.fetch('refreshToken')
    ))
  end

  def token_refresh_needed(response_body, retry_counter, user, store)
    token_expired?(response_body['errorCode']) && retry_counter < 1 && refresh_user_token(user, store)
  end
end
