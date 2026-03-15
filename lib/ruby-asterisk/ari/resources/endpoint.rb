# frozen_string_literal: true

module RubyAsterisk
  module ARI
    module Resources
      # Represents an ARI Endpoint resource (a SIP/PJSIP/DAHDI endpoint).
      class Endpoint < Base
        def technology
          data['technology']
        end

        def resource
          data['resource']
        end

        def state
          data['state']
        end
      end
    end
  end
end
