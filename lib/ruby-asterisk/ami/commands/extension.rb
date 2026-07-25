# frozen_string_literal: true

module RubyAsterisk
  module AMI
    module Commands
      ##
      #
      # Extension commands
      #
      module Extension
        def extension_state(exten:, context:, action_id: nil)
          execute 'ExtensionState', { 'Exten' => exten, 'Context' => context, 'ActionID' => action_id }
        end
      end
    end
  end
end
