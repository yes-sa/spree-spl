# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UpdateSpartaStateJob, type: :job do
  let!(:order) do
    create(
      :order,
      state: 'complete'
    )
  end

  let(:order_token)  { order.token }
  let(:order_number) { order.number }
  let(:card_number)  { '1234567890123' }
  let(:basket)       { [{ 'name' => 'Item', 'price' => 100 }] }
  let(:iso_date)     { DateTime.now.iso8601 }

  let!(:store) do
    order.store.tap do |s|
      s.update!(
        private_metadata: {
          'spl_url' => 'https://spl.test',
          'spl_api_user' => 'user',
          'spl_api_token' => 'token',
          'spl_partner_code' => 'partner',
          'spl_place_code' => 'place',
          'spl_update_status_mode' => 'mode',
          'spl_prg_code' => 'PRG',
          'spl_mode' => 'mode',
          'spl_pos_key' => 'poskey'
        }
      )
    end
  end

  let(:find_tx) do
    {
      'errorCode' => '0',
      'response' => [
        { 'date' => iso_date, 'cardNo' => card_number, 'basket' => basket }
      ]
    }
  end

  before do
    allow(Spl::UrlCreatorService).to receive(:new).and_return(
      double(
        sale: 'https://spl.test/sale',
        find: 'https://spl.test/find',
        sale_refund: 'https://spl.test/refund'
      )
    )
  end

  def stub_http_responses(*bodies)
    http = double('NetHTTP')
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    responses = bodies.map do |body|
      instance_double(Net::HTTPResponse, body: body.to_json, is_a?: true)
    end
    allow(http).to receive(:request).and_return(*responses)
  end

  describe '#perform' do
    context "state = 'D' (update order)" do
      let(:success_response) { { 'errorCode' => '0' } }

      it 'finds transaction and updates order' do
        stub_http_responses(find_tx, success_response)

        expect do
          described_class.perform_now(order_token, 'D', order_number, store)
        end.not_to raise_error
      end
    end

    context "state = 'C' (refund)" do
      let(:refund_response) { { 'errorCode' => '0' } }

      it 'finds transaction and performs refund' do
        order.update(state: 'canceled')
        stub_http_responses(find_tx, refund_response)

        expect do
          described_class.perform_now(order_token, 'C', order_number, store)
        end.not_to raise_error
      end
    end

    context 'when find_transaction returns ORDER_NOT_FOUND' do
      let(:order_not_found_response) { { 'errorCode' => 'ORDER_NOT_FOUND' } }

      it 'exits without raising error' do
        stub_http_responses(order_not_found_response)

        expect do
          described_class.perform_now(order_token, 'D', order_number, store)
        end.not_to raise_error
      end
    end

    context 'when find_transaction returns REQUEST_ALREADY_PROCESSED' do
      let(:request_already_processed_response) { { 'errorCode' => 'REQUEST_ALREADY_PROCESSED' } }

      it 'exits without raising error' do
        stub_http_responses(request_already_processed_response)

        expect do
          described_class.perform_now(order_token, 'D', order_number, store)
        end.not_to raise_error
      end
    end

    context 'when unhandled error returned' do
      let(:bad_response) { { 'errorCode' => '999', 'msg' => 'Unexpected error' } }

      it 'raises StandardError' do
        stub_http_responses(find_tx, bad_response)

        expect do
          described_class.perform_now(order_token, 'D', order_number, store)
        end.to raise_error(StandardError)
      end
    end
  end
end
