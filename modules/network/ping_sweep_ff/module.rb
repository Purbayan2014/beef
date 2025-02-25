#
# Copyright (c) 2006-2022 Wade Alcorn - wade@bindshell.net
# Browser Exploitation Framework (BeEF) - http://beefproject.com
# See the file 'doc/COPYING' for copying permission
#
#
# Ping Sweep Module - jgaliana
# Discover active hosts in the internal network of the hooked browser.
# It works calling a Java method from JavaScript and do not require user interaction.


class Ping_sweep_ff < BeEF::Core::Command
  
  def self.options
    return [
        {'name' => 'ipRange', 'ui_label' => 'Scan IP range (C class or IP)', 'value' => '192.168.0.1-192.168.0.254'},
        {'name' => 'timeout', 'ui_label' => 'Timeout (ms)', 'value' => '2000'},
        {'name' => 'delay', 'ui_label' => 'Delay between requests (ms)', 'value' => '100'}
    ]
  end
  
  def post_execute
    content = {}
    content['host'] =@datastore['host'] if not @datastore['host'].nil?
    if content.empty?
      content['fail'] = 'No active hosts have been discovered.'
    end
    save content

    configuration = BeEF::Core::Configuration.instance
    if configuration.get("beef.extension.network.enable") == true

      session_id = @datastore['beefhook']

      # save the network host
      if @datastore['results'] =~ /host=([\d\.]+) is alive/
        ip = $1
        if BeEF::Filters.is_valid_ip?(ip)
          print_debug("Hooked browser has network interface #{ip}")
          BeEF::Core::Models::NetworkHost.create(:hooked_browser_id => session_id, :ip => ip)
        end
      end
    end

  end
end
