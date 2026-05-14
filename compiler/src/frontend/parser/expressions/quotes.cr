require "../expressions"

module Emerald
  class Parser
    private def parse_unquote_expr : AST::UnquoteExpr
      start_tok = expect(TokenType::Dollar)
      expect(TokenType::LParen)
      expression = parse_expression
      expect(TokenType::RParen)

      AST::UnquoteExpr.new(expression).at(start_tok.line, start_tok.col).as(AST::UnquoteExpr)
    end

    private def parse_quote_expr : AST::QuoteExpr
      start_tok = expect(TokenType::Identifier)
      kind_tok = expect(TokenType::Identifier)
      kind = kind_tok.value

      expect(TokenType::LBrace)

      quoted = case kind
               when "expr"
                 node = parse_expression
                 expect(TokenType::RBrace)
                 node
               when "stmt"
                 node = parse_statement
                 expect(TokenType::RBrace)
                 node
               when "block"
                 statements = [] of AST::Node

                 until peek.type == TokenType::RBrace || at_end?
                   statements << parse_statement
                 end

                 expect(TokenType::RBrace)
                 AST::Block.new(statements).at(start_tok.line, start_tok.col).as(AST::Node)
               when "method"
                 method = parse_quoted_method
                 expect(TokenType::RBrace)
                 method
               when "field"
                 field = parse_quoted_field
                 expect(TokenType::RBrace)
                 field
               else
                 raise ParseError.new("Unknown quote kind '#{kind}'. Expected expr, stmt, block, method or field", kind_tok.line, kind_tok.col)
               end

      AST::QuoteExpr.new(kind, quoted).at(start_tok.line, start_tok.col).as(AST::QuoteExpr)
    end

    private def parse_quoted_field : AST::FieldDecl
      start_tok = peek
      vis = parse_visibility
      mutability = parse_mutability
      type_ref = parse_type_ref
      name_tok = expect(TokenType::Identifier)

      initializer : AST::Node? = nil

      if peek.type == TokenType::Eq
        consume
        initializer = parse_expression
      end

      expect(TokenType::Semicolon)

      AST::FieldDecl.new(vis, mutability, type_ref, name_tok.value, initializer)
        .at(start_tok.line, start_tok.col).as(AST::FieldDecl)
    end

    private def parse_quoted_method : AST::MethodDecl
      start_tok = peek
      vis = parse_visibility
      parse_mutability

      ret_type = parse_type_ref
      name_tok = expect(TokenType::Identifier)

      expect(TokenType::LParen)
      params = parse_params
      expect(TokenType::RParen)

      body : AST::Block? = nil

      if peek.type == TokenType::Semicolon
        consume
      elsif peek.type == TokenType::Arrow
        consume
        expr = parse_expression
        expect(TokenType::Semicolon)
        ret_stmt = AST::ReturnStmt.new(expr).at(start_tok.line, start_tok.col).as(AST::ReturnStmt)
        body = AST::Block.new([ret_stmt.as(AST::Node)]).at(start_tok.line, start_tok.col).as(AST::Block)
      else
        body = parse_block_expr
      end

      AST::MethodDecl.new(vis, name_tok.value, params, ret_type, body, false, false, false)
        .at(start_tok.line, start_tok.col).as(AST::MethodDecl)
    end

  end
end
