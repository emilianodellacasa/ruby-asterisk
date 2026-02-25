# frozen_string_literal: true

module RubyAsterisk
  module AMI
    module Commands
      ##
      #
      # Conference commands
      #
      module Conference
        def meet_me_list
          execute 'MeetMeList'
        end

        def confbridges
          execute 'ConfbridgeListRooms'
        end

        def confbridge(conference)
          execute 'ConfbridgeList', { 'Conference' => conference }
        end

        def confbridge_mute(conference:, channel:)
          execute 'ConfbridgeMute', { 'Conference' => conference, 'Channel' => channel }
        end

        def confbridge_unmute(conference:, channel:)
          execute 'ConfbridgeUnmute', { 'Conference' => conference, 'Channel' => channel }
        end

        def confbridge_kick(conference:, channel:)
          execute 'ConfbridgeKick', { 'Conference' => conference, 'Channel' => channel }
        end
      end
    end
  end
end
