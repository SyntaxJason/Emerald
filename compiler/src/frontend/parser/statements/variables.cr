require "../statements"

module Emerald
  class Parser
    private def parse_var_decl_stmt : AST::VarDecl
      tok = peek
      mutability = parse_mutability
      type_ref = parse_type_ref
      name_tok = expect(TokenType::Identifier)
      expect(TokenType::Eq)
      init = parse_expression
      expect(TokenType::Semicolon)
      AST::VarDecl.new(mutability, type_ref, name_tok.value, init).at(tok.line, tok.col).as(AST::VarDecl)
    end

    private def parse_assignment : AST::AssignStmt
      name_tok = expect(TokenType::Identifier)
      expect(TokenType::Eq)
      value = parse_expression
      expect(TokenType::Semicolon)
      AST::AssignStmt.new(name_tok.value, value).at(name_tok.line, name_tok.col).as(AST::AssignStmt)
    end

    private def parse_expr_or_assign_stmt : AST::Node
      tok = peek
      expr = parse_expression
      if peek.type == TokenType::Eq && expr.is_a?(AST::MemberAccess)
        consume
        value = parse_expression
        expect(TokenType::Semicolon)
        ma = expr.as(AST::MemberAccess)
        return AST::ExpressionStmt.new(
          AST::MemberAssign.new(ma.receiver, ma.name, value).at(tok.line, tok.col)
        ).at(tok.line, tok.col)
      end
      expect(TokenType::Semicolon)
      AST::ExpressionStmt.new(expr).at(tok.line, tok.col)
    end

  end
end
