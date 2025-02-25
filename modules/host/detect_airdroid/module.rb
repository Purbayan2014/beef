#
# Copyright (c) 2006-2022 Wade Alcorn - wade@bindshell.net
# Browser Exploitation Framework (BeEF) - http://beefproject.com
# See the file 'doc/COPYING' for copying permission
#

class Detect_airdroid < BeEF::Core::Command

  def self.options
    return [
        {'name' => 'ipHost', 'ui_label' => 'IP or Hostname', 'value' => '127.0.0.1'},
        {'name' => 'port' , 'ui_label' => 'Port', 'value' => '8888'}
  ]
  end
  
  def post_execute
    save({'airdroid' => @datastore['airdroid']})

    configuration = BeEF::Core::Configuration.instance
    if configuration.get("beef.extension.network.enable") == true
      if @datastore['results'] =~ /^proto=(https?)&ip=([\d\.]+)&port=([\d]+)&airdroid=Installed$/
        proto = $1
        ip = $2
        port = $3
        session_id = @datastore['beefhook']
        type = 'Airdroid'
        if BeEF::Filters.is_valid_ip?(ip)
          print_debug("Hooked browser found 'Airdroid' [proto: #{proto}, ip: #{ip}, port: #{port}]")
          BeEF::Core::Models::NetworkService.create(:hooked_browser_id => session_id, :proto => proto, :ip => ip, :port => port, :type => type)
        end
      end
    end
  end
  
end
