# frozen_string_literal: true

module RubyAsterisk
  module ARI
    module Resources
      # Represents an ARI Playback resource with media-control action methods.
      class Playback < Base
        def stop
          client.delete("/ari/playbacks/#{id}")
        end

        def control(operation)
          client.post("/ari/playbacks/#{id}/control", { operation: operation })
        end
      end
    end
  end
end
