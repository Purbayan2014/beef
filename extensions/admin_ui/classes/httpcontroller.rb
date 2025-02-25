#
# Copyright (c) 2006-2022 Wade Alcorn - wade@bindshell.net
# Browser Exploitation Framework (BeEF) - http://beefproject.com
# See the file 'doc/COPYING' for copying permission
#
module BeEF
module Extension
module AdminUI
    
  #
  # Handle HTTP requests and call the relevant functions in the derived classes
  #
  class HttpController 
    
    attr_accessor :headers, :status, :body, :paths, :currentuser, :params
    
    C = BeEF::Core::Models::Command
    CM = BeEF::Core::Models::CommandModule
    Z = BeEF::Core::Models::HookedBrowser
    
    #
    # Class constructor. Takes data from the child class and populates itself with it.
    #
    def initialize(data = {})
      @erubis = nil
      @status = 200 if data['status'].nil?
      @session = BeEF::Extension::AdminUI::Session.instance

      @config = BeEF::Core::Configuration.instance
      @bp = @config.get "beef.extension.admin_ui.base_path"

      @headers = {'Content-Type' => 'text/html; charset=UTF-8'} if data['headers'].nil?

      if data['paths'].nil? and self.methods.include? "index"
        @paths = {'index' => '/'} 
      else
        @paths = data['paths']
      end
    end

    # 
    # Authentication check. Confirm the request to access the UI comes from a permitted IP address
    # 
    def authenticate_request(ip)
      auth = BeEF::Extension::AdminUI::Controllers::Authentication.new
      if !auth.permitted_source?(ip)
        if @config.get("beef.http.web_server_imitation.enable")
          type = @config.get("beef.http.web_server_imitation.type")
          case type
            when "apache"
              @body = BeEF::Core::Router::APACHE_BODY
              @status = 404
              @headers = BeEF::Core::Router::APACHE_HEADER
              return false
            when "iis"
              @body = BeEF::Core::Router::IIS_BODY
              @status = 404
              @headers = BeEF::Core::Router::IIS_HEADER
              return false
            when "nginx"
              @body = BeEF::Core::Router::APACHE_BODY
              @status = 404
              @headers = BeEF::Core::Router::APACHE_HEADER
              return false
            else
              @body = "Not Found."
              @status = 404
              @headers = {"Content-Type" => "text/html"}
              return false
          end
        else
          @body = "Not Found."
          @status = 404
          @headers = {"Content-Type" => "text/html"}
          return false
        end
      else
        return true
      end
    end

    # 
    # Check if reverse proxy has been enabled and return the correct client IP address
    # 
    def get_ip(request)
      if !@config.get("beef.http.allow_reverse_proxy")
        ua_ip = request.get_header('REMOTE_ADDR') # Get client remote ip address
      else
        ua_ip = request.ip # Get client x-forwarded-for ip address
      end
      ua_ip
    end
    
    
    #
    # Handle HTTP requests and call the relevant functions in the derived classes
    #
    def run(request, response)
      @request = request
      @params = request.params

      # Web UI base path, like http://beef_domain/<bp>/panel
      auth_url = "#{@bp}/authentication"

      # If access to the UI is not permitted for the request IP address return a 404
      if !authenticate_request(get_ip(@request))
        return
      end

      # test if session is unauth'd and whether the auth functionality is requested
      if not @session.valid_session?(@request) and not self.class.eql?(BeEF::Extension::AdminUI::Controllers::Authentication)
        @body = ''
        @status = 302
        @headers = {'Location' => auth_url}
        return
      end
      
      # get the mapped function (if it exists) from the derived class
      path = request.path_info
      (print_error "path is invalid";return) if not BeEF::Filters.is_valid_path_info?(path)
      function = @paths[path] || @paths[path + '/'] # check hash for '<path>' and '<path>/'
      (print_error "[Admin UI] Path does not exist: #{path}";return) if function.nil?
      
      # call the relevant mapped function
      function.call

      # build the template filename and apply it - if the file exists
      function_name = function.name # used for filename
      class_s = self.class.to_s.sub('BeEF::Extension::AdminUI::Controllers::', '').downcase # used for directory name
      template_ui = "#{$root_dir}/extensions/admin_ui/controllers/#{class_s}/#{function_name}.html"
      @eruby = Erubis::FastEruby.new(File.read(template_ui)) if File.exists? template_ui # load the template file
      @body = @eruby.result(binding()) if not @eruby.nil? # apply template and set the response

      # set appropriate content-type 'application/json' for .json files
      @headers['Content-Type']='application/json; charset=UTF-8' if request.path =~ /\.json$/

      # set content type
      if @headers['Content-Type'].nil?
        @headers['Content-Type']='text/html; charset=UTF-8' # default content and charset type for all pages
      end
    rescue => e
      print_error "Error handling HTTP request: #{e.message}"
      print_error e.backtrace
    end

    # Constructs a html script tag (from media/javascript directory)
    def script_tag(filename)
      "<script src=\"#{@bp}/media/javascript/#{filename}\" type=\"text/javascript\"></script>"
    end

    # Constructs a html script tag (from media/javascript-min directory)
    def script_tag_min(filename)
      "<script src=\"#{@bp}/media/javascript-min/#{filename}\" type=\"text/javascript\"></script>"
    end

    # Constructs a html stylesheet tag
    def stylesheet_tag(filename)
      "<link rel=\"stylesheet\" href=\"#{@bp}/media/css/#{filename}\" type=\"text/css\" />"
    end

    # Constructs a hidden html nonce tag
    def nonce_tag 
      "<input type=\"hidden\" name=\"nonce\" id=\"nonce\" value=\"#{@session.get_nonce}\"/>"
    end

    def base_path
      @bp.to_s
    end

    private
    
    @eruby
    
    # Unescapes a URL-encoded string.
    def unescape(s)
      s.tr('+', ' ').gsub(/%([\da-f]{2})/in){[$1].pack('H*')}
    end
  end
end
end
end
