# frozen_string_literal: true

require 'faraday'
require 'json'

module RubyAsterisk
  module ARI
    # HTTP client for the Asterisk REST Interface (ARI).
    # Wraps Faraday to provide authenticated GET, POST, and DELETE requests
    # and maps HTTP error responses to RubyAsterisk::Error exceptions.
    class Client
      attr_reader :base_url, :app_name

      def initialize(base_url, api_key, app_name)
        @base_url = base_url
        @app_name = app_name
        @connection = Faraday.new(url: base_url) do |conn|
          conn.request :authorization, :basic, api_key, ''
          conn.headers['Content-Type'] = 'application/json'
          conn.headers['Accept'] = 'application/json'
        end
      end

      def get(path, params = {})
        response = @connection.get(path, params)
        handle_response(response)
      end

      def post(path, body = {})
        response = @connection.post(path, body.to_json)
        handle_response(response)
      end

      def delete(path, params = {})
        response = @connection.delete(path, params)
        handle_response(response)
      end

      def asterisk_info
        get('/ari/asterisk/info')
      end

      private

      def handle_response(response)
        raise Error, error_message(response) if response.status >= 400

        parse_body(response.body)
      end

      def error_message(response)
        parsed = parse_body(response.body)
        parsed.is_a?(Hash) ? parsed['message'] || response.reason_phrase : response.reason_phrase
      rescue StandardError
        response.reason_phrase
      end

      def parse_body(body)
        return nil if body.nil? || body.empty?

        JSON.parse(body)
      rescue JSON::ParserError
        body
      end
    end
  end
end
