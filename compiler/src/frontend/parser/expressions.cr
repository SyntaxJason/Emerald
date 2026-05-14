module Emerald
  class Parser
    def parse_expression(min_prec : Int32 = PREC_ASSIGN) : AST::Node
      left = parse_unary
      while !at_end?
        op_info = BINARY_OPS[peek.type]?
        break if op_info.nil?
        prec = op_info[:prec]
        break if prec < min_prec
        op_tok = consume
        next_prec = op_info[:right_assoc] ? prec : prec + 1
        right = parse_expression(next_prec)

        if op_info[:name] == ".."
          left = AST::RangeExpr.new(left, right, true).at(op_tok.line, op_tok.col)
          next
        end

        left = AST::BinaryOp.new(op_info[:name], left, right).at(op_tok.line, op_tok.col)
      end
      left
    end

    private def parse_unary : AST::Node
      if peek.type == TokenType::Minus || peek.type == TokenType::Bang || peek.type == TokenType::Plus
        op_tok = consume
        operand = parse_unary
        return AST::UnaryOp.new(op_tok.value, operand).at(op_tok.line, op_tok.col)
      end
      parse_postfix
    end

    private def parse_postfix : AST::Node
      expr = parse_primary
      loop do
        case peek.type
        when TokenType::Dot
          consume
          name_tok = expect(TokenType::Identifier)
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
            if peek.type == TokenType::LBrace
              args << parse_trailing_lambda
            end
            expr = AST::MethodCall.new(expr, name_tok.value, args).at(name_tok.line, name_tok.col)
          elsif peek.type == TokenType::LBrace
            args = [] of AST::Node
            args << parse_trailing_lambda
            expr = AST::MethodCall.new(expr, name_tok.value, args).at(name_tok.line, name_tok.col)
          else
            expr = AST::MemberAccess.new(expr, name_tok.value).at(name_tok.line, name_tok.col)
          end
        when TokenType::LBracket
          consume
          index = parse_expression
          expect(TokenType::RBracket)
          expr = AST::IndexExpr.new(expr, index).at(expr.line, expr.col)
        else
          break
        end
      end
      expr
    end

    private def parse_trailing_lambda : AST::LambdaExpr
      start_tok = expect(TokenType::LBrace)
      params = [] of AST::Param
      uses_it = false

      saved = @pos
      if peek.type == TokenType::Identifier && peek_at(@pos + 1).try(&.type) == TokenType::Arrow
        pname = consume
        consume
        params << AST::Param.new(
          AST::NamedType.new("Any").at(pname.line, pname.col).as(AST::NamedType),
          pname.value
        ).at(pname.line, pname.col).as(AST::Param)
      else
        @pos = saved
        uses_it = true
      end

      body_start = @pos
      stmts = [] of AST::Node
      until peek.type == TokenType::RBrace || at_end?
        stmt_start = @pos
        if can_be_trailing_expression?
          expr = parse_expression
          if peek.type == TokenType::RBrace
            stmts << AST::ExpressionStmt.new(expr).at(start_tok.line, start_tok.col)
            break
          else
            @pos = stmt_start
            stmts << parse_statement
          end
        else
          stmts << parse_statement
        end
      end
      body_end = @pos
      expect(TokenType::RBrace)

      if uses_it && @tokens[body_start...body_end].any? { |t| t.type == TokenType::Identifier && t.value == "it" }
        params << AST::Param.new(
          AST::NamedType.new("Any").at(start_tok.line, start_tok.col).as(AST::NamedType),
          "it"
        ).at(start_tok.line, start_tok.col).as(AST::Param)
      end

      body = AST::Block.new(stmts).at(start_tok.line, start_tok.col).as(AST::Block)
      AST::LambdaExpr.new(params, nil, body, false).at(start_tok.line, start_tok.col).as(AST::LambdaExpr)
    end

    private def can_be_trailing_expression? : Bool
      stmt_keywords = [
        TokenType::KwIf, TokenType::KwWhile, TokenType::KwFor,
        TokenType::KwReturn, TokenType::KwBreak, TokenType::KwContinue,
        TokenType::KwFinal, TokenType::KwCryo, TokenType::LBrace,
      ]
      return false if stmt_keywords.includes?(peek.type)
      return false if looks_like_var_decl?
      true
    end

  end
end

require "./expressions/primary"
require "./expressions/quotes"
require "./expressions/identifiers"
require "./expressions/lambdas"
require "./expressions/match"
require "./expressions/interpolation"
