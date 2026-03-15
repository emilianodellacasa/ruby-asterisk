# frozen_string_literal: true

module RubyAsterisk
  module ARI
    module Resources
      # Base class providing shared data access for ARI resource objects.
      # Subclasses receive raw JSON data and a client reference, then expose
      # domain-specific action methods that delegate HTTP calls to the client.
      class Base
        attr_reader :data, :client

        def initialize(data, client)
          @data = data
          @client = client
        end

        def id
          data['id']
        end
      end
    end
  end
end
