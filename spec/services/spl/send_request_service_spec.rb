# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spl::SendRequestService, type: :service do
  let(:url) { URI.parse('https://spl.test/api/send-otp') }
  let(:body) { { foo: 'bar', nested: { a: 1 } } }

  let(:http) { instance_double(Net::HTTP) }
  let(:response) { instance_double(Net::HTTPResponse) }

  before do
    allow(Rails.logger).to receive(:debug)
  end

  describe '#call' do
    it 'builds a POST request with JSON content-type and sends it over SSL' do
      expect(Net::HTTP).to receive(:new).with(url.host, url.port).and_return(http)
      expect(http).to receive(:use_ssl=).with(true)

      # We want to assert on the actual request object created
      expect(http).to receive(:request) do |request|
        expect(request).to be_a(Net::HTTP::Post)
        expect(request['Content-Type']).to eq('application/json')
        expect(request.body).to eq(body.to_json)
        response
      end.and_return(response)

      result = described_class.new(url, body).call
      expect(result).to eq(response)
    end

    it 'logs the request body with [SPL REQUEST BODY] prefix' do
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)

      expect(Rails.logger).to receive(:debug).with("[SPL REQUEST BODY] #{body.to_json.inspect}")

      allow(http).to receive(:request).and_return(response)

      described_class.new(url, body).call
    end
  end
end
