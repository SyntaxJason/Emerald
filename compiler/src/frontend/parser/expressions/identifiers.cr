require "../expressions"

module Emerald
  class Parser
    private def parse_identifier_or_qualified : AST::Node
      name_tok = consume
      ns_path = [] of String

      while peek.type == TokenType::ColonColon
        ns_path << name_tok.value
        consume
        if peek.type == TokenType::Identifier || keyword_token?(peek.type)
          name_tok = consume
        else
          name_tok = expect(TokenType::Identifier)
        end
        if peek.type != TokenType::ColonColon && (peek.type == TokenType::LParen || !ident_continues?)
          break
        end
      end

      if (name_tok.value == "Ok" || name_tok.value == "Err") && peek.type == TokenType::LParen && ns_path.empty?
        consume
        inner = parse_expression
        expect(TokenType::RParen)
        if name_tok.value == "Ok"
          return AST::OkExpr.new(inner).at(name_tok.line, name_tok.col)
        else
          return AST::ErrExpr.new(inner).at(name_tok.line, name_tok.col)
        end
      end

      if peek.type == TokenType::ColonColon
        consume
        method_tok = expect(TokenType::Identifier)
        first = name_tok.value[0]
        if first.uppercase?
          return AST::MethodRef.new(nil, name_tok.value, method_tok.value).at(name_tok.line, name_tok.col)
        else
          recv = AST::Identifier.new(name_tok.value).at(name_tok.line, name_tok.col).as(AST::Node)
          return AST::MethodRef.new(recv, nil, method_tok.value).at(name_tok.line, name_tok.col)
        end
      end

      if peek.type == TokenType::LParen
        consume
        args = [] of AST::Node
        unless peek.type == TokenType::RParen
          loop do
            args << parse_expression
            break unless peek.type == TokenType::Comma
            consume
          end
        end
        expect(TokenType::RParen)
        first = name_tok.value[0]
        if first.uppercase?
          node = AST::NewExpr.new(name_tok.value, args).at(name_tok.line, name_tok.col).as(AST::NewExpr)
          node.namespace_path = ns_path
          node
        else
          node = AST::CallExpr.new(name_tok.value, args).at(name_tok.line, name_tok.col).as(AST::CallExpr)
          node.namespace_path = ns_path
          node
        end
      else
        node = AST::Identifier.new(name_tok.value).at(name_tok.line, name_tok.col).as(AST::Identifier)
        node.namespace_path = ns_path
        node
      end
    end

    private def ident_continues? : Bool
      true
    end

  end
end
