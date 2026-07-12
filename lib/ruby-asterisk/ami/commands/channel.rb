# frozen_string_literal: true

module RubyAsterisk
  module AMI
    module Commands
      ##
      #
      # Channel commands
      #
      module Channel
        def core_show_channels
          execute 'CoreShowChannels'
        end

        def status(channel: nil, action_id: nil)
          execute 'Status', { 'Channel' => channel, 'ActionID' => action_id }
        end

        def originate(channel, context, callee, priority, variable: nil, caller_id: nil, timeout: 30_000, async: nil)
          execute 'Originate',
                  { 'Channel' => channel, 'Context' => context, 'Exten' => callee, 'Priority' => priority,
                    'CallerID' => caller_id || channel, 'Timeout' => timeout.to_s, 'Variable' => variable,
                    'Async' => async },
                  timeout: [@timeout, timeout / 1000].max
        end

        def originate_app(channel:, application:, data:, async:)
          execute 'Originate',
                  { 'Channel' => channel, 'Application' => application, 'Data' => data, 'Timeout' => '30000',
                    'Async' => async }
        end

        def channels
          execute 'Command', { 'Command' => 'show channels' }
        end

        def redirect(channel, context, callee, priority, variable: nil, caller_id: nil, timeout: 30_000)
          execute 'Redirect',
                  { 'Channel' => channel, 'Context' => context, 'Exten' => callee, 'Priority' => priority,
                    'CallerID' => caller_id || channel, 'Timeout' => timeout.to_s, 'Variable' => variable },
                  timeout: [@timeout, timeout / 1000].max
        end

        def hangup(channel)
          execute 'Hangup', { 'Channel' => channel }
        end

        def atxfer(channel:, exten:, context:, priority: '1')
          execute 'Atxfer',
                  { 'Channel' => channel, 'Exten' => exten.to_s, 'Context' => context, 'Priority' => priority }
        end
      end
    end
  end
end
