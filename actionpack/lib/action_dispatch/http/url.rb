# frozen_string_literal: true

require "active_support/core_ext/module/attribute_accessors"
require "action_dispatch/http/uri"

module ActionDispatch
  module Http
    module URL
      IP_HOST_REGEXP  = /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/
      HOST_REGEXP     = /(^[^:]+:\/\/)?(\[[^\]]+\]|[^:]+)(?::(\d+$))?/
      PROTOCOL_REGEXP = /^([^:]+)(:)?(\/\/)?$/

      mattr_accessor :secure_protocol, default: false
      mattr_accessor :tld_length, default: 1

      attr :uri
      delegate :optional_port, to: :uri

      class << self
        def url_for(options)
          if options[:only_path]
            path_for options
          else
            full_url_for options
          end
        end

        def full_url_for(options)
          host     = options[:host]
          protocol = options[:protocol]
          port     = options[:port]

          unless host
            raise ArgumentError, "Missing host to link to! Please provide the :host parameter, set default_url_options[:host], or set :only_path to true"
          end

          build_host_url(host, port, protocol, options, path_for(options))
        end

        def path_for(options)
          path = options[:script_name].to_s.chomp("/")
          path << options[:path] if options.key?(:path)

          path = "/" if options[:trailing_slash] && path.blank?

          add_params(path, options[:params]) if options.key?(:params)
          add_anchor(path, options[:anchor]) if options.key?(:anchor)

          path
        end

        private
          def add_params(path, params)
            params = { params: params } unless params.is_a?(Hash)
            params.reject! { |_, v| v.to_param.nil? }
            query = params.to_query
            path << "?#{query}" unless query.empty?
          end

          def add_anchor(path, anchor)
            if anchor
              path << "##{Journey::Router::Utils.escape_fragment(anchor.to_param)}"
            end
          end

          def add_trailing_slash(path)
            if path.include?("?")
              path.sub!(/\?/, '/\&')
            elsif !path.include?(".")
              path.sub!(/[^\/]\z|\A\z/, '\&/')
            end
          end

          def build_host_url(host, port, protocol, options, path)
            if match = host.match(HOST_REGEXP)
              protocol ||= match[1] unless protocol == false
              host       = match[2]
              port       = match[3] unless options.key? :port
            end

            protocol = normalize_protocol protocol
            host     = normalize_host(host, options)

            result = protocol.dup

            if options[:user] && options[:password]
              result << "#{Rack::Utils.escape(options[:user])}:#{Rack::Utils.escape(options[:password])}@"
            end

            result << host
            normalize_port(port, protocol) { |normalized_port|
              result << ":#{normalized_port}"
            }

            result.concat path
          end

          def named_host?(host)
            !IP_HOST_REGEXP.match?(host)
          end

          def normalize_protocol(protocol)
            case protocol
            when nil
              secure_protocol ? "https://" : "http://"
            when false, "//"
              "//"
            when PROTOCOL_REGEXP
              "#{$1}://"
            else
              raise ArgumentError, "Invalid :protocol option: #{protocol.inspect}"
            end
          end

          def normalize_host(_host, options)
            return _host unless named_host?(_host)

            tld_length = options[:tld_length] || @@tld_length
            subdomain  = options.fetch :subdomain, true
            domain     = options[:domain]

            host = +""
            if subdomain == true
              return _host if domain.nil?

              host << ActionDispatch::Http::URI.extract_subdomains(_host, tld_length).join(".")
            elsif subdomain
              host << subdomain.to_param
            end
            host << "." unless host.empty?
            host << (domain || ActionDispatch::Http::URI.extract_domain(_host, tld_length))
            host
          end

          def normalize_port(port, protocol)
            return unless port

            case protocol
            when "//" then yield port
            when "https://"
              yield port unless port.to_i == 443
            else
              yield port unless port.to_i == 80
            end
          end
      end

      def initialize
        super
        @uri = ActionDispatch::Http::URI.build_from_faulty_string(request_url)
        @protocol = nil
        @port     = nil
      end

      # Returns the complete URL used for this request.
      #
      #   req = ActionDispatch::Request.new 'HTTP_HOST' => 'example.com'
      #   req.url # => "http://example.com"
      def url
        request_url
      end

      # Returns the host for this request, such as "example.com".
      #
      #   req = ActionDispatch::Request.new 'HTTP_HOST' => 'example.com:8080'
      #   req.host # => "example.com"
      def host
        @uri.host
      end

      # Returns the port number of this request as an integer.
      #
      #   req = ActionDispatch::Request.new 'HTTP_HOST' => 'example.com'
      #   req.port # => 80
      #
      #   req = ActionDispatch::Request.new 'HTTP_HOST' => 'example.com:8080'
      #   req.port # => 8080
      def port
        @uri.port
      end

      # Returns 'https://' if this is an SSL request and 'http://' otherwise.
      #
      #   req = ActionDispatch::Request.new 'HTTP_HOST' => 'example.com'
      #   req.protocol # => "http://"
      #
      #   req = ActionDispatch::Request.new 'HTTP_HOST' => 'example.com', 'HTTPS' => 'on'
      #   req.protocol # => "https://"
      def protocol
        @uri.protocol
      end

      # Returns the standard \port number for this request's protocol.
      #
      #   req = ActionDispatch::Request.new 'HTTP_HOST' => 'example.com:8080'
      #   req.standard_port # => 80
      def standard_port
        ssl? ? 443 : 80
      end

      # Returns whether this request is using the standard port
      #
      #   req = ActionDispatch::Request.new 'HTTP_HOST' => 'example.com:80'
      #   req.standard_port? # => true
      #
      #   req = ActionDispatch::Request.new 'HTTP_HOST' => 'example.com:8080'
      #   req.standard_port? # => false
      def standard_port?
        request_port == standard_port
      end

      # Returns a string \port suffix, including colon, like ":8080" if the \port
      # number of this request is not the default HTTP \port 80 or HTTPS \port 443.
      #
      #   req = ActionDispatch::Request.new 'HTTP_HOST' => 'example.com:80'
      #   req.port_string # => ""
      #
      #   req = ActionDispatch::Request.new 'HTTP_HOST' => 'example.com:8080'
      #   req.port_string # => ":8080"
      def port_string
        standard_port? ? "" : ":#{request_port}"
      end

      # Returns a \host:\port string for this request, such as "example.com" or
      # "example.com:8080". Port is only included if it is not a default port
      # (80 or 443)
      #
      #   req = ActionDispatch::Request.new 'HTTP_HOST' => 'example.com'
      #   req.host_with_port # => "example.com"
      #
      #   req = ActionDispatch::Request.new 'HTTP_HOST' => 'example.com:80'
      #   req.host_with_port # => "example.com"
      #
      #   req = ActionDispatch::Request.new 'HTTP_HOST' => 'example.com:8080'
      #   req.host_with_port # => "example.com:8080"
      def host_with_port
        "#{request_host}#{port_string}"
      end

      #   req = ActionDispatch::Request.new 'HTTP_HOST' => 'example.com:80'
      #   req.raw_host_with_port # => "example.com:80"
      #
      #   req = ActionDispatch::Request.new 'HTTP_HOST' => 'example.com:8080'
      #   req.raw_host_with_port # => "example.com:8080"
      def raw_host_with_port
        if forwarded = x_forwarded_host.presence
          forwarded.split(/,\s?/).last
        else
          get_header("HTTP_HOST") || "#{server_name}:#{get_header('SERVER_PORT')}"
        end
      end

      # Returns the host for this request, such as "example.com".
      #
      #   req = ActionDispatch::Request.new 'HTTP_HOST' => 'example.com:8080'
      #   req.request_host # => "example.com"
      def request_host
        raw_host_with_port.sub(/:\d+$/, "")
      end

      # Returns the requested port, such as 8080, based on SERVER_PORT
      #
      #   req = ActionDispatch::Request.new 'SERVER_PORT' => '80'
      #   req.server_port # => 80
      #
      #   req = ActionDispatch::Request.new 'SERVER_PORT' => '8080'
      #   req.server_port # => 8080
      def server_port
        get_header("SERVER_PORT").to_i
      end

      # Returns the \domain part of a \host, such as "rubyonrails.org" in "www.rubyonrails.org". You can specify
      # a different <tt>tld_length</tt>, such as 2 to catch rubyonrails.co.uk in "www.rubyonrails.co.uk".
      def domain(tld_length = @@tld_length)
        ActionDispatch::Http::URI.extract_domain(host, tld_length)
      end

      # Returns all the \subdomains as an array, so <tt>["dev", "www"]</tt> would be
      # returned for "dev.www.rubyonrails.org". You can specify a different <tt>tld_length</tt>,
      # such as 2 to catch <tt>["www"]</tt> instead of <tt>["www", "rubyonrails"]</tt>
      # in "www.rubyonrails.co.uk".
      def subdomains(tld_length = @@tld_length)
        ActionDispatch::Http::URI.extract_subdomains(host, tld_length)
      end

      # Returns all the \subdomains as a string, so <tt>"dev.www"</tt> would be
      # returned for "dev.www.rubyonrails.org". You can specify a different <tt>tld_length</tt>,
      # such as 2 to catch <tt>"www"</tt> instead of <tt>"www.rubyonrails"</tt>
      # in "www.rubyonrails.co.uk".
      def subdomain(tld_length = @@tld_length)
        ActionDispatch::Http::URI.extract_subdomain(host, tld_length)
      end

      private
        def request_url
          request_protocol + host_with_port + fullpath
        end

        def request_port
          @port ||= if raw_host_with_port =~ /:(\d+)$/
            $1.to_i
          else
            standard_port
          end
        end

        def request_protocol
          @protocol ||= ssl? ? "https://" : "http://"
        end
    end
  end
end
