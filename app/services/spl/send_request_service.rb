# frozen_string_literal: true

require 'net/http'
require 'json'

module Spl
  class SendRequestService
    def initialize(url, body)
      @url = url
      @body = body
    end

    def call
      send_request
    end

    private

    def send_request
      http = Net::HTTP.new(@url.host, @url.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(@url)
      request['Content-Type'] = 'application/json'
      request.body = @body.to_json
      Rails.logger.debug "[SPL REQUEST BODY] #{request.body.inspect}"
      http.request(request)
    end
  end
end
