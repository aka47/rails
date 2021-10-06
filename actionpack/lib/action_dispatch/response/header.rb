# frozen_string_literal: true

module ActionDispatch
  class Response
    class Header < DelegateClass(Hash) # :nodoc:
      def initialize(response, header)
        @response = response
        super(header)
      end

      def []=(k, v)
        if @response.sending? || @response.sent?
          raise ActionDispatch::IllegalStateError, "header already sent"
        end

        super
      end

      def merge(other)
        self.class.new @response, __getobj__.merge(other)
      end

      def to_hash
        __getobj__.dup
      end
    end
  end
end
