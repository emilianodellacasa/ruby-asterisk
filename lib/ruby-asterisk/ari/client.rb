# frozen_string_literal: true

require 'faraday'
require 'json'
require 'ruby-asterisk/ari/resources/base'
require 'ruby-asterisk/ari/resources/channel'
require 'ruby-asterisk/ari/resources/bridge'
require 'ruby-asterisk/ari/resources/playback'
require 'ruby-asterisk/ari/resources/endpoint'
require 'ruby-asterisk/ari/resources/collection'

module RubyAsterisk
  module ARI
    # HTTP client for the Asterisk REST Interface (ARI).
    # Wraps Faraday to provide authenticated GET, POST, and DELETE requests
    # and maps HTTP error responses to RubyAsterisk::Error exceptions.
    class Client
      attr_reader :base_url, :app_name

      def initialize(base_url, api_key, app_name)
        @base_url = base_url
        @api_key = api_key
        @app_name = app_name
        # ARI credentials may be supplied as "user:password" (the standard
        # api_key form). Split on the first colon; a bare key means empty password.
        user, pass = api_key.to_s.split(':', 2)
        pass ||= ''
        @connection = Faraday.new(url: base_url) do |conn|
          conn.request :authorization, :basic, user, pass
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

      def channels
        Resources::Collection.new(Resources::Channel, '/ari/channels', self)
      end

      def bridges
        Resources::Collection.new(Resources::Bridge, '/ari/bridges', self)
      end

      def playbacks
        Resources::Collection.new(Resources::Playback, '/ari/playbacks', self)
      end

      def endpoints
        Resources::Collection.new(Resources::Endpoint, '/ari/endpoints', self)
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
