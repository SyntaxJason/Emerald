require "../lexer"

module Emerald
  class Lexer
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
             when '$' then TokenType::Dollar
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
