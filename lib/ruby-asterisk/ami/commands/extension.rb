# frozen_string_literal: true

module RubyAsterisk
  module AMI
    module Commands
      module Extension
        def parked_calls
          execute 'ParkedCalls'
        end

        def extension_state(exten:, context:, action_id: nil)
          execute 'ExtensionState', { 'Exten' => exten, 'Context' => context, 'ActionID' => action_id }
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
      end
    end
  end
end
