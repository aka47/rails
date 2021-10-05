# frozen_string_literal: true

require "active_support/core_ext/module/attribute_accessors"
require "action_dispatch/http/url"

module ActionDispatch
  class Request
    module BuildUrlFromRequest
      attr :uri
      delegate :optional_port, to: :uri

      def initialize
        super
        begin
          @uri = ActionDispatch::Http::URL.new(request_url)
        rescue ::URI::InvalidURIError, URI::InvalidComponentError
          @uri = ActionDispatch::Http::URL.new("")
        end
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
      def domain(tld_length = ActionDispatch::Http::URL.tld_length)
        ActionDispatch::Http::URL.extract_domain(host, tld_length)
      end

      # Returns all the \subdomains as an array, so <tt>["dev", "www"]</tt> would be
      # returned for "dev.www.rubyonrails.org". You can specify a different <tt>tld_length</tt>,
      # such as 2 to catch <tt>["www"]</tt> instead of <tt>["www", "rubyonrails"]</tt>
      # in "www.rubyonrails.co.uk".
      def subdomains(tld_length = ActionDispatch::Http::URL.tld_length)
        ActionDispatch::Http::URL.extract_subdomains(host, tld_length)
      end

      # Returns all the \subdomains as a string, so <tt>"dev.www"</tt> would be
      # returned for "dev.www.rubyonrails.org". You can specify a different <tt>tld_length</tt>,
      # such as 2 to catch <tt>"www"</tt> instead of <tt>"www.rubyonrails"</tt>
      # in "www.rubyonrails.co.uk".
      def subdomain(tld_length = ActionDispatch::Http::URL.tld_length)
        ActionDispatch::Http::URL.extract_subdomain(host, tld_length)
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
