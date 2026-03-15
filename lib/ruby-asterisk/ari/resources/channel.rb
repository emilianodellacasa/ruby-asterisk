# frozen_string_literal: true

module RubyAsterisk
  module ARI
    module Resources
      # Represents an ARI Channel resource with call-control action methods.
      class Channel < Base
        def ring
          client.post("/ari/channels/#{id}/ring")
        end

        def answer
          client.post("/ari/channels/#{id}/answer")
        end

        def hangup
          client.delete("/ari/channels/#{id}")
        end

        def play(media, params = {})
          client.post("/ari/channels/#{id}/play", { media: media }.merge(params))
        end
      end
    end
  end
end
