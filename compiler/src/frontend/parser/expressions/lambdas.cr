require "../expressions"

module Emerald
  class Parser
    def looks_like_lambda? : Bool
      return false unless peek.type == TokenType::LParen
      if peek_at(@pos + 1).try(&.type) == TokenType::RParen &&
         peek_at(@pos + 2).try(&.type) == TokenType::Arrow
        return true
      end
      t1 = peek_at(@pos + 1).try(&.type)
      t2 = peek_at(@pos + 2).try(&.type)
      if is_type_start?(t1) && t2 == TokenType::Identifier
        depth = 1
        i = @pos + 1
        while i < @tokens.size && depth > 0
          tt = @tokens[i].type
          case tt
          when TokenType::LParen then depth += 1
          when TokenType::RParen
            depth -= 1
            if depth == 0
              return @tokens[i + 1]?.try(&.type) == TokenType::Arrow
            end
          end
          i += 1
        end
      end
      false
    end

    private def parse_lambda : AST::LambdaExpr
      start_tok = expect(TokenType::LParen)
      params = [] of AST::Param
      unless peek.type == TokenType::RParen
        loop do
          ptype = parse_type_ref
          pname = expect(TokenType::Identifier)
          params << AST::Param.new(ptype, pname.value).at(pname.line, pname.col).as(AST::Param)
          break unless peek.type == TokenType::Comma
          consume
        end
      end
      expect(TokenType::RParen)
      expect(TokenType::Arrow)

      if peek.type == TokenType::LBrace
        body = parse_block_expr
        AST::LambdaExpr.new(params, nil, body, false).at(start_tok.line, start_tok.col).as(AST::LambdaExpr)
      else
        body = parse_expression
        AST::LambdaExpr.new(params, nil, body, true).at(start_tok.line, start_tok.col).as(AST::LambdaExpr)
      end
    end

    private def parse_block_expr : AST::Block
      tok = expect(TokenType::LBrace)
      stmts = [] of AST::Node
      until peek.type == TokenType::RBrace || at_end?
        stmts << parse_statement
      end
      expect(TokenType::RBrace)
      AST::Block.new(stmts).at(tok.line, tok.col).as(AST::Block)
    end

  end
end
