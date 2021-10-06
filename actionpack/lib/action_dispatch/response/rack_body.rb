# frozen_string_literal: true

module ActionDispatch
  class Response
    class RackBody
      def initialize(response)
        @response = response
      end

      def each(*args, &block)
        @response.each(*args, &block)
      end

      def close
        # Rack "close" maps to Response#abort, and *not* Response#close
        # (which is used when the controller's finished writing)
        @response.abort
      end

      def body
        @response.body
      end

      def respond_to?(method, include_private = false)
        if method.to_sym == :to_path
          @response.stream.respond_to?(method)
        else
          super
        end
      end

      def to_path
        @response.stream.to_path
      end

      def to_ary
        nil
      end
    end
  end
end
