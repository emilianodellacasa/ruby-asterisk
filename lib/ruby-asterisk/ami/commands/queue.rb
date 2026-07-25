# frozen_string_literal: true

module RubyAsterisk
  module AMI
    module Commands
      ##
      #
      # Queue commands
      #
      module Queue
        def queues
          execute 'Queues', {}
        end

        def queue_add(queue, interface, penalty: 2, paused: false, member_name: '')
          execute 'QueueAdd',
                  { 'Queue' => queue, 'Interface' => interface, 'Penalty' => penalty, 'Paused' => paused,
                    'MemberName' => member_name }
        end

        def queue_remove(queue:, interface:)
          execute 'QueueRemove', { 'Queue' => queue, 'Interface' => interface }
        end

        def queue_status
          execute 'QueueStatus'
        end

        def queue_summary(queue)
          execute 'QueueSummary', { 'Queue' => queue }
        end

        def queue_pause(interface:, paused:, queue:, reason: 'none')
          execute 'QueuePause', { 'Interface' => interface, 'Paused' => paused, 'Queue' => queue, 'Reason' => reason }
        end
      end
    end
  end
end
