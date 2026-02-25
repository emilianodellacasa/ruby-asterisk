# frozen_string_literal: true

module RubyAsterisk
  module AMI
    module Commands
      module Sip
        def sip_peers
          execute 'SIPpeers'
        end

        def sip_show_peer(peer)
          execute 'SIPshowpeer', { 'Peer' => peer }
        end

        def sip_show_registry
          execute 'SIPshowregistry'
        end
      end
    end
  end
end
