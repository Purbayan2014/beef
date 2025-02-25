#
# Copyright (c) 2006-2022 Wade Alcorn - wade@bindshell.net
# Browser Exploitation Framework (BeEF) - http://beefproject.com
# See the file 'doc/COPYING' for copying permission
#

require 'extensions/notifications/channels/tweet'
require 'extensions/notifications/channels/email'
require 'extensions/notifications/channels/pushover'
require 'extensions/notifications/channels/slack_workspace'

module BeEF
module Extension
module Notifications

  #
  # Notifications class
  #
  class Notifications

    def initialize(from, event, time_now, hb)
      @config = BeEF::Core::Configuration.instance
      if @config.get('beef.extension.notifications.enable') == false
        # notifications are not enabled
        return nil
      else
        @from = from
        @event = event
        @time_now = time_now
        @hb = hb
      end

      message = "#{from} #{event} #{time_now} #{hb}"

      if @config.get('beef.extension.notifications.twitter.enable') == true
        username = @config.get('beef.extension.notifications.twitter.target_username')
        BeEF::Extension::Notifications::Channels::Tweet.new(username,message)
      end

      if @config.get('beef.extension.notifications.email.enable') == true
        to_address    = @config.get('beef.extension.notifications.email.to_address')
        BeEF::Extension::Notifications::Channels::Email.new(to_address,message)
      end

      if @config.get('beef.extension.notifications.pushover.enable') == true
        BeEF::Extension::Notifications::Channels::Pushover.new(message)
      end

      if @config.get('beef.extension.notifications.slack.enable') == true
        BeEF::Extension::Notifications::Channels::SlackWorkspace.new(message)
      end
    end

  end
  
end
end
end
