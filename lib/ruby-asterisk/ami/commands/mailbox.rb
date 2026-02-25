# frozen_string_literal: true

module RubyAsterisk
  module AMI
    module Commands
      module Mailbox
        def mailbox_status(mailbox:, context: 'default')
          execute 'MailboxStatus', { 'Mailbox' => "#{mailbox}@#{context}" }
        end

        def mailbox_count(mailbox:, context: 'default')
          execute 'MailboxCount', { 'Mailbox' => "#{mailbox}@#{context}" }
        end
      end
    end
  end
end
