# frozen_string_literal: true

module RubyAsterisk
  module ARI
    class WebSocket
      # Minimal socket wrapper handed to WebSocket::Driver.client: the driver
      # reads #url to build the handshake request (including Basic auth from
      # the URL userinfo) and calls #write to emit outgoing bytes.
      class SocketAdapter
        attr_reader :url

        def initialize(url, io)
          @url = url
          @io = io
        end

        def write(data)
          @io.write(data)
        end
      end
    end
  end
end
