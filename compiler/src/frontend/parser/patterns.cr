require "./base"

module Emerald
  class Parser
    def parse_pattern : AST::Pattern
      tok = peek
      case tok.type
      when TokenType::Identifier
        if tok.value == "_"
          consume
          return AST::WildcardPattern.new.at(tok.line, tok.col).as(AST::WildcardPattern)
        end
        if tok.value == "null"
          consume
          return AST::NullPattern.new.at(tok.line, tok.col).as(AST::NullPattern)
        end
        name_tok = consume
        if peek.type == TokenType::LParen
          consume
          subs = [] of AST::Pattern
          unless peek.type == TokenType::RParen
            loop do
              subs << parse_pattern
              break unless peek.type == TokenType::Comma
              consume
            end
          end
          expect(TokenType::RParen)
          AST::DestructurePattern.new(name_tok.value, subs).at(name_tok.line, name_tok.col).as(AST::DestructurePattern)
        else
          AST::BindPattern.new(name_tok.value).at(name_tok.line, name_tok.col).as(AST::BindPattern)
        end
      when TokenType::KwIs
        consume
        type_tok = consume
        type_name = case type_tok.type
                    when TokenType::KwInt    then "Int"
                    when TokenType::KwFloat  then "Float"
                    when TokenType::KwBool   then "Bool"
                    when TokenType::KwChar   then "Char"
                    when TokenType::KwString then "String"
                    when TokenType::Identifier then type_tok.value
                    else
                      raise ParseError.new("Expected type after 'is', got #{type_tok.type}", type_tok.line, type_tok.col)
                    end
        binding : String? = nil
        if peek.type == TokenType::Identifier && peek.value != "_"
          binding = consume.value
        end
        AST::TypePattern.new(type_name, binding).at(tok.line, tok.col).as(AST::TypePattern)
      when TokenType::IntLit, TokenType::FloatLit, TokenType::StringLit,
           TokenType::CharLit, TokenType::TrueLit, TokenType::FalseLit
        first = parse_pattern_literal
        if peek.type == TokenType::DotDot
          consume
          finish = parse_pattern_literal
          AST::RangePattern.new(first, finish, true).at(tok.line, tok.col).as(AST::RangePattern)
        else
          AST::LiteralPattern.new(first).at(tok.line, tok.col).as(AST::LiteralPattern)
        end
      when TokenType::Minus
        consume
        inner = parse_pattern_literal
        case inner
        when AST::IntLiteral
          neg = AST::IntLiteral.new(-inner.value).at(tok.line, tok.col)
          AST::LiteralPattern.new(neg).at(tok.line, tok.col).as(AST::LiteralPattern)
        when AST::FloatLiteral
          neg = AST::FloatLiteral.new(-inner.value).at(tok.line, tok.col)
          AST::LiteralPattern.new(neg).at(tok.line, tok.col).as(AST::LiteralPattern)
        else
          raise ParseError.new("Unary minus only valid before numeric literal in pattern", tok.line, tok.col)
        end
      else
        raise ParseError.new("Expected pattern, got #{tok.type} ('#{tok.value}')", tok.line, tok.col)
      end
    end

    private def parse_pattern_literal : AST::Node
      tok = consume
      case tok.type
      when TokenType::IntLit    then AST::IntLiteral.new(tok.value.to_i64).at(tok.line, tok.col)
      when TokenType::FloatLit  then AST::FloatLiteral.new(tok.value.to_f64).at(tok.line, tok.col)
      when TokenType::StringLit then AST::StringLiteral.new(tok.value).at(tok.line, tok.col)
      when TokenType::CharLit   then AST::CharLiteral.new(tok.value).at(tok.line, tok.col)
      when TokenType::TrueLit   then AST::BoolLiteral.new(true).at(tok.line, tok.col)
      when TokenType::FalseLit  then AST::BoolLiteral.new(false).at(tok.line, tok.col)
      else
        raise ParseError.new("Expected literal, got #{tok.type}", tok.line, tok.col)
      end
    end
  end
end
