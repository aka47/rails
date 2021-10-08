# frozen_string_literal: true

module ActionDispatch
  class Response
    private
      class Buffer # :nodoc:
        def initialize(response, buf)
          @response = response
          @buf      = buf
          @closed   = false
          @str_body = nil
        end

        def body
          @str_body ||= begin
            buf = +""
            each { |chunk| buf << chunk }
            buf
          end
        end

        def write(string)
          raise IOError, "closed stream" if closed?

          @str_body = nil
          @response.commit!
          @buf.push string
        end

        def each(&block)
          if @str_body
            return enum_for(:each) unless block_given?

            yield @str_body
          else
            each_chunk(&block)
          end
        end

        def abort
        end

        def close
          @response.commit!
          @closed = true
        end

        def closed?
          @closed
        end

        private
          def each_chunk(&block)
            @buf.each(&block)
          end
      end
  end
end
