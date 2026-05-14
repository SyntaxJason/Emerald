require "../lexer"

module Emerald
  class Lexer
    private def read_number : Token
      start_line, start_col = @line, @col
      buf = String.build do |b|
        while @pos < @source.size && @source[@pos].ascii_number?
          b << @source[@pos]
          @pos += 1
          @col += 1
        end
        if @pos < @source.size && @source[@pos] == '.' && peek_at(@pos + 1).try(&.ascii_number?)
          b << @source[@pos]
          @pos += 1
          @col += 1
          while @pos < @source.size && @source[@pos].ascii_number?
            b << @source[@pos]
            @pos += 1
            @col += 1
          end
          return Token.new(TokenType::FloatLit, b.to_s, start_line, start_col)
        end
      end
      Token.new(TokenType::IntLit, buf, start_line, start_col)
    end

    private def read_identifier_or_keyword : Token
      start_line, start_col = @line, @col
      buf = String.build do |b|
        while @pos < @source.size && (@source[@pos].ascii_alphanumeric? || @source[@pos] == '_')
          b << @source[@pos]
          @pos += 1
          @col += 1
        end
      end
      type = KEYWORDS[buf]? || TokenType::Identifier
      Token.new(type, buf, start_line, start_col)
    end

    private def read_string : Token
      start_line, start_col = @line, @col
      @pos += 1
      @col += 1

      parts = [] of InterpPart
      current_text = ""
      raw = ""
      has_interp = false

      while @pos < @source.size && @source[@pos] != '"'
        c = @source[@pos]
        if c == '\\' && @pos + 1 < @source.size
          esc = @source[@pos + 1]
          replacement = case esc
                        when 'n'  then "\n"
                        when 't'  then "\t"
                        when 'r'  then "\r"
                        when '\\' then "\\"
                        when '"'  then "\""
                        when '\'' then "'"
                        when '$'  then "$"
                        when '0'  then "\0"
                        else
                          raise LexError.new("Unknown escape sequence \\#{esc}", @line, @col)
                        end
          current_text += replacement
          raw += "#{c}#{esc}"
          @pos += 2
          @col += 2
        elsif c == '$' && peek_at(@pos + 1) == '('
          has_interp = true
          parts << InterpPart.new(InterpPart::Kind::Text, current_text)
          current_text = ""
          raw += "$("
          @pos += 2
          @col += 2

          depth = 1
          expr_text = ""
          while @pos < @source.size && depth > 0
            ec = @source[@pos]
            if ec == '('
              depth += 1
              expr_text += ec.to_s
            elsif ec == ')'
              depth -= 1
              break if depth == 0
              expr_text += ec.to_s
            else
              expr_text += ec.to_s
            end
            if ec == '\n'
              @line += 1
              @col = 1
            else
              @col += 1
            end
            @pos += 1
          end
          if @pos >= @source.size
            raise LexError.new("Unterminated string interpolation", start_line, start_col)
          end
          parts << InterpPart.new(InterpPart::Kind::Expr, expr_text)
          raw += "#{expr_text})"
          @pos += 1
          @col += 1
        else
          current_text += c.to_s
          raw += c.to_s
          if c == '\n'
            @line += 1
            @col = 1
          else
            @col += 1
          end
          @pos += 1
        end
      end

      if @pos >= @source.size
        raise LexError.new("Unterminated string", start_line, start_col)
      end
      @pos += 1
      @col += 1

      if has_interp
        parts << InterpPart.new(InterpPart::Kind::Text, current_text)
        Token.new(TokenType::InterpString, raw, start_line, start_col, parts)
      else
        Token.new(TokenType::StringLit, current_text, start_line, start_col)
      end
    end

    private def read_char : Token
      start_line, start_col = @line, @col
      @pos += 1
      @col += 1
      if @pos >= @source.size
        raise LexError.new("Unterminated char literal", start_line, start_col)
      end
      value = if @source[@pos] == '\\' && @pos + 1 < @source.size
                esc = @source[@pos + 1]
                @pos += 2
                @col += 2
                case esc
                when 'n'  then "\n"
                when 't'  then "\t"
                when 'r'  then "\r"
                when '\\' then "\\"
                when '\'' then "'"
                when '"'  then "\""
                when '0'  then "\0"
                else
                  raise LexError.new("Unknown escape \\#{esc}", start_line, start_col)
                end
              else
                v = @source[@pos].to_s
                @pos += 1
                @col += 1
                v
              end
      if @pos >= @source.size || @source[@pos] != '\''
        raise LexError.new("Unterminated char literal", start_line, start_col)
      end
      @pos += 1
      @col += 1
      Token.new(TokenType::CharLit, value, start_line, start_col)
    end

  end
end
