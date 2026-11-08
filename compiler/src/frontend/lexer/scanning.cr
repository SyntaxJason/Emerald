require "../lexer"

module Emerald
  class Lexer
    private def skip_whitespace_and_comments
      while @pos < @source.size
        c = @source[@pos]
        if c.whitespace?
          if c == '\n'
            @line += 1
            @col = 1
          else
            @col += 1
          end
          @pos += 1
        elsif c == '/' && peek_at(@pos + 1) == '/'
          while @pos < @source.size && @source[@pos] != '\n'
            @pos += 1
          end
        elsif c == '/' && peek_at(@pos + 1) == '*'
          @pos += 2
          @col += 2
          while @pos < @source.size - 1 && !(@source[@pos] == '*' && @source[@pos + 1] == '/')
            if @source[@pos] == '\n'
              @line += 1
              @col = 1
            else
              @col += 1
            end
            @pos += 1
          end
          if @pos < @source.size - 1
            @pos += 2
            @col += 2
          end
        else
          break
        end
      end
    end

    private def peek_at(i : Int32) : Char?
      return nil if i >= @source.size
      @source[i]
    end

  end
end
