# frozen_string_literal: true

module RubyAsterisk
  module AMI
    module Commands
      module Monitor
        def monitor(channel, mix: false, file: nil, format: 'wav')
          execute 'Monitor', { 'Channel' => channel, 'File' => file, 'Mix' => mix, 'Format' => format }
        end

        def stop_monitor(channel)
          execute 'StopMonitor', { 'Channel' => channel }
        end

        def pause_monitor(channel)
          execute 'PauseMonitor', { 'Channel' => channel }
        end

        def unpause_monitor(channel)
          execute 'UnpauseMonitor', { 'Channel' => channel }
        end

        def change_monitor(channel:, file:)
          execute 'ChangeMonitor', { 'Channel' => channel, 'File' => file }
        end
      end
    end
  end
end
