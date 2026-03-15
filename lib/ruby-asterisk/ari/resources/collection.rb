# frozen_string_literal: true

module RubyAsterisk
  module ARI
    module Resources
      # Provides a typed collection interface for fetching ARI resources.
      # Enables the Active Record-style pattern: client.channels.get(id).
      class Collection
        def initialize(resource_class, base_path, client)
          @resource_class = resource_class
          @base_path = base_path
          @client = client
        end

        def get(id)
          data = @client.get("#{@base_path}/#{id}")
          @resource_class.new(data, @client)
        end

        def list(params = {})
          data = @client.get(@base_path, params)
          data.map { |item| @resource_class.new(item, @client) }
        end
      end
    end
  end
end
