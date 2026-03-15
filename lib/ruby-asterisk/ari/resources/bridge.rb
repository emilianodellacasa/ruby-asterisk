# frozen_string_literal: true

module RubyAsterisk
  module ARI
    module Resources
      # Represents an ARI Bridge resource with channel-mixing action methods.
      class Bridge < Base
        def add_channel(channel_id)
          client.post("/ari/bridges/#{id}/addChannel", { channel: channel_id })
        end

        def remove_channel(channel_id)
          client.post("/ari/bridges/#{id}/removeChannel", { channel: channel_id })
        end

        def destroy
          client.delete("/ari/bridges/#{id}")
        end
      end
    end
  end
end
