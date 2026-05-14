require "../expressions"

module Emerald
  class Parser
    private def parse_primary : AST::Node
      tok = peek
      case tok.type
      when TokenType::IntLit
        consume
        AST::IntLiteral.new(tok.value.to_i64).at(tok.line, tok.col)
      when TokenType::FloatLit
        consume
        AST::FloatLiteral.new(tok.value.to_f64).at(tok.line, tok.col)
      when TokenType::StringLit
        consume
        AST::StringLiteral.new(tok.value).at(tok.line, tok.col)
      when TokenType::InterpString
        consume
        parts = parse_interp_parts(tok)
        AST::StringInterp.new(parts).at(tok.line, tok.col)
      when TokenType::CharLit
        consume
        AST::CharLiteral.new(tok.value).at(tok.line, tok.col)
      when TokenType::TrueLit
        consume
        AST::BoolLiteral.new(true).at(tok.line, tok.col)
      when TokenType::FalseLit
        consume
        AST::BoolLiteral.new(false).at(tok.line, tok.col)
      when TokenType::KwMatch
        parse_match_expr
      when TokenType::LParen
        if looks_like_lambda?
          parse_lambda
        else
          consume
          inner = parse_expression
          expect(TokenType::RParen)
          inner
        end
      when TokenType::KwThis
        consume
        AST::ThisExpr.new.at(tok.line, tok.col)
      when TokenType::LBracket
        consume
        elements = [] of AST::Node
        unless peek.type == TokenType::RBracket
          loop do
            elements << parse_expression
            break unless peek.type == TokenType::Comma
            consume
          end
        end
        expect(TokenType::RBracket)
        AST::ListLiteral.new(elements).at(tok.line, tok.col)
      when TokenType::Identifier
        if tok.value == "quote" && peek_at(@pos + 1).try(&.type) == TokenType::Identifier &&
           peek_at(@pos + 2).try(&.type) == TokenType::LBrace
          parse_quote_expr
        else
          parse_identifier_or_qualified
        end
      when TokenType::Dollar
        parse_unquote_expr
      else
        if keyword_token?(tok.type)
          consume
          AST::Identifier.new(tok.value).at(tok.line, tok.col)
        else
          raise ParseError.new("Unexpected token #{tok.type} ('#{tok.value}')", tok.line, tok.col)
        end
      end
    end

  end
end
