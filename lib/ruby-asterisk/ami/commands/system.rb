# frozen_string_literal: true

module RubyAsterisk
  module AMI
    module Commands
      ##
      #
      # System commands
      #
      module System
        def login(username:, secret:)
          connect unless connected
          execute 'Login', { 'Username' => username, 'Secret' => secret, 'Event' => 'On' }
        end

        def logoff
          execute 'Logoff'
        end

        def ping
          execute 'Ping'
        end

        def event_mask(event_mask = 'off')
          execute 'Events', { 'EventMask' => event_mask }
        end

        def command(command)
          execute 'Command', { 'Command' => command }
        end

        def wait_event(timeout: -1)
          @timeout = [@timeout, timeout].max
          execute 'WaitEvent', { 'Timeout' => timeout }
        end
      end
    end
  end
end
