require "./token"

module Emerald
  class LexError < Exception
    getter line : Int32
    getter col : Int32

    def initialize(message : String, @line, @col)
      super("#{message} at #{@line}:#{@col}")
    end
  end

  class Lexer
    KEYWORDS = {
      "Int"        => TokenType::KwInt,
      "Float"      => TokenType::KwFloat,
      "Bool"       => TokenType::KwBool,
      "Char"       => TokenType::KwChar,
      "String"     => TokenType::KwString,
      "Void"       => TokenType::KwVoid,
      "final"      => TokenType::KwFinal,
      "cryo"       => TokenType::KwCryo,
      "public"     => TokenType::KwPublic,
      "private"    => TokenType::KwPrivate,
      "protected"  => TokenType::KwProtected,
      "internal"   => TokenType::KwInternal,
      "if"         => TokenType::KwIf,
      "else"       => TokenType::KwElse,
      "while"      => TokenType::KwWhile,
      "for"        => TokenType::KwFor,
      "in"         => TokenType::KwIn,
      "return"     => TokenType::KwReturn,
      "break"      => TokenType::KwBreak,
      "continue"   => TokenType::KwContinue,
      "class"      => TokenType::KwClass,
      "interface"  => TokenType::KwInterface,
      "data"       => TokenType::KwData,
      "extends"    => TokenType::KwExtends,
      "implements" => TokenType::KwImplements,
      "this"       => TokenType::KwThis,
      "default"    => TokenType::KwDefault,
      "abstract"   => TokenType::KwAbstract,
      "match"      => TokenType::KwMatch,
      "is"         => TokenType::KwIs,
      "namespace"  => TokenType::KwNamespace,
      "alias"      => TokenType::KwAlias,
      "main"       => TokenType::KwMain,
      "true"       => TokenType::TrueLit,
      "false"      => TokenType::FalseLit,
    }

    def initialize(@source : String)
      @pos = 0
      @line = 1
      @col = 1
    end

    def tokenize : Array(Token)
      tokens = [] of Token
      loop do
        skip_whitespace_and_comments
        break if @pos >= @source.size

        c = @source[@pos]
        case
        when c == '"'
          tokens << read_string
        when c == '\''
          tokens << read_char
        when c.ascii_number?
          tokens << read_number
        when c.ascii_letter? || c == '_'
          tokens << read_identifier_or_keyword
        else
          tokens << read_operator_or_punct
        end
      end
      tokens << Token.new(TokenType::EOF, "", @line, @col)
      tokens
    end

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

    private def read_operator_or_punct : Token
      start_line, start_col = @line, @col
      c = @source[@pos]

      two = @pos + 1 < @source.size ? "#{c}#{@source[@pos + 1]}" : nil
      case two
      when "=="
        @pos += 2; @col += 2
        return Token.new(TokenType::EqEq, "==", start_line, start_col)
      when "!="
        @pos += 2; @col += 2
        return Token.new(TokenType::NotEq, "!=", start_line, start_col)
      when "<="
        @pos += 2; @col += 2
        return Token.new(TokenType::LtEq, "<=", start_line, start_col)
      when ">="
        @pos += 2; @col += 2
        return Token.new(TokenType::GtEq, ">=", start_line, start_col)
      when "&&"
        @pos += 2; @col += 2
        return Token.new(TokenType::AndAnd, "&&", start_line, start_col)
      when "||"
        @pos += 2; @col += 2
        return Token.new(TokenType::OrOr, "||", start_line, start_col)
      when "->"
        @pos += 2; @col += 2
        return Token.new(TokenType::Arrow, "->", start_line, start_col)
      when ".."
        @pos += 2; @col += 2
        return Token.new(TokenType::DotDot, "..", start_line, start_col)
      when "::"
        @pos += 2; @col += 2
        return Token.new(TokenType::ColonColon, "::", start_line, start_col)
      end

      type = case c
             when '+' then TokenType::Plus
             when '-' then TokenType::Minus
             when '*' then TokenType::Star
             when '/' then TokenType::Slash
             when '%' then TokenType::Percent
             when '=' then TokenType::Eq
             when '<' then TokenType::Lt
             when '>' then TokenType::Gt
             when '!' then TokenType::Bang
             when '(' then TokenType::LParen
             when ')' then TokenType::RParen
             when '{' then TokenType::LBrace
             when '}' then TokenType::RBrace
             when '[' then TokenType::LBracket
             when ']' then TokenType::RBracket
             when ',' then TokenType::Comma
             when ';' then TokenType::Semicolon
             when '.' then TokenType::Dot
             when '@' then TokenType::At
             when ':' then TokenType::Colon
             else
               raise LexError.new("Unexpected character '#{c}'", @line, @col)
             end

      tok = Token.new(type, c.to_s, start_line, start_col)
      @pos += 1
      @col += 1
      tok
    end
  end
end
