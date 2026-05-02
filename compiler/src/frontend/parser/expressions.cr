require "./base"
require "./types"
require "./patterns"

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
      while peek.type == TokenType::Dot
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
      when TokenType::Identifier
        parse_identifier_or_qualified
      else
        raise ParseError.new("Unexpected token #{tok.type} ('#{tok.value}')", tok.line, tok.col)
      end
    end

    private def parse_identifier_or_qualified : AST::Node
      name_tok = consume
      ns_path = [] of String

      while peek.type == TokenType::ColonColon
        ns_path << name_tok.value
        consume
        name_tok = expect(TokenType::Identifier)
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

    private def parse_match_expr : AST::MatchExpr
      start_tok = expect(TokenType::KwMatch)
      subject = parse_expression
      expect(TokenType::LBrace)
      arms = [] of AST::MatchArm
      while peek.type != TokenType::RBrace && !at_end?
        arms << parse_match_arm
      end
      expect(TokenType::RBrace)
      AST::MatchExpr.new(subject, arms).at(start_tok.line, start_tok.col).as(AST::MatchExpr)
    end

    private def parse_match_arm : AST::MatchArm
      start_tok = peek
      patterns = [] of AST::Pattern
      patterns << parse_pattern
      while peek.type == TokenType::Comma
        consume
        patterns << parse_pattern
      end
      guard : AST::Node? = nil
      if peek.type == TokenType::KwIf
        consume
        guard = parse_expression
      end
      expect(TokenType::Arrow)
      body : AST::Node
      if peek.type == TokenType::LBrace
        body = parse_block_expr
        consume if peek.type == TokenType::Semicolon
      else
        body = parse_expression
        expect(TokenType::Semicolon)
      end
      AST::MatchArm.new(patterns, guard, body).at(start_tok.line, start_tok.col).as(AST::MatchArm)
    end

    private def parse_interp_parts(tok : Token) : Array(AST::InterpSegment)
      raw_parts = tok.parts.not_nil!
      result = [] of AST::InterpSegment
      raw_parts.each do |part|
        case part.kind
        when InterpPart::Kind::Text
          result << AST::InterpText.new(part.content)
        when InterpPart::Kind::Expr
          sub_tokens = Lexer.new(part.content).tokenize
          sub_parser = Parser.new(sub_tokens)
          expr = sub_parser.parse_expression
          unless sub_parser.at_end?
            raise ParseError.new("Unexpected tokens in interpolation", tok.line, tok.col)
          end
          result << AST::InterpExpr.new(expr)
        end
      end
      result
    end
  end
end
