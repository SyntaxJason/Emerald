require "../expressions"

module Emerald
  class Parser
    def looks_like_lambda? : Bool
      return false unless peek.type == TokenType::LParen

      if peek_at(@pos + 1).try(&.type) == TokenType::RParen &&
         peek_at(@pos + 2).try(&.type) == TokenType::Arrow
        return true
      end

      return true if looks_like_untyped_lambda_params?
      looks_like_typed_lambda_params?
    end

    private def looks_like_untyped_lambda_params? : Bool
      i = @pos + 1
      return false unless @tokens[i]?.try(&.type) == TokenType::Identifier

      loop do
        return false unless @tokens[i]?.try(&.type) == TokenType::Identifier
        i += 1

        case @tokens[i]?.try(&.type)
        when TokenType::Comma
          i += 1
        when TokenType::RParen
          return @tokens[i + 1]?.try(&.type) == TokenType::Arrow
        else
          return false
        end
      end
    end

    private def looks_like_typed_lambda_params? : Bool
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
          ptype, pname = parse_lambda_param
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

    private def parse_lambda_param : Tuple(AST::TypeRef, Token)
      if looks_like_untyped_lambda_param?
        pname = expect(TokenType::Identifier)
        return {AST::NamedType.new("Any").at(pname.line, pname.col).as(AST::TypeRef), pname}
      end

      ptype = parse_type_ref
      pname = expect(TokenType::Identifier)
      {ptype, pname}
    end

    private def looks_like_untyped_lambda_param? : Bool
      return false unless peek.type == TokenType::Identifier

      next_type = peek_at(@pos + 1).try(&.type)
      next_type == TokenType::Comma || next_type == TokenType::RParen
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
