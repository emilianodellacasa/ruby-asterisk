# frozen_string_literal: true

module RubyAsterisk
  module AMI
    module Commands
      ##
      #
      # System commands
      #
      module System
        def parked_calls
          execute 'ParkedCalls'
        end

        def device_state_list
          execute 'DeviceStateList'
        end

        def skinny_devices
          execute 'SKINNYdevices'
        end

        def skinny_lines
          execute 'SKINNYlines'
        end

        def ping
          execute 'Ping'
        end

        def event_mask(event_mask = 'off')
          execute 'Events', { 'EventMask' => event_mask }
        end

        def wait_event(timeout: -1)
          execute 'WaitEvent', { 'Timeout' => timeout }, timeout: [@timeout, timeout].max
        end

        def command(command)
          execute 'Command', { 'Command' => command }
        end
      end
    end
  end
end
