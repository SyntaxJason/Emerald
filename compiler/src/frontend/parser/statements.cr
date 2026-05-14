module Emerald
  class Parser
    def parse_statement : AST::Node
      case peek.type
      when TokenType::LBrace   then parse_block
      when TokenType::KwIf     then parse_if
      when TokenType::KwWhile  then parse_while
      when TokenType::KwFor    then parse_for
      when TokenType::KwReturn then parse_return
      when TokenType::KwBreak
        tok = consume; expect(TokenType::Semicolon)
        AST::BreakStmt.new.at(tok.line, tok.col)
      when TokenType::KwContinue
        tok = consume; expect(TokenType::Semicolon)
        AST::ContinueStmt.new.at(tok.line, tok.col)
      when TokenType::KwFinal, TokenType::KwCryo
        parse_var_decl_stmt
      else
        if looks_like_var_decl?
          parse_var_decl_stmt
        elsif peek.type == TokenType::Identifier && peek_at(@pos + 1).try(&.type) == TokenType::Eq
          parse_assignment
        else
          parse_expr_or_assign_stmt
        end
      end
    end

  end
end

require "./statements/looks_like"
require "./statements/variables"
require "./statements/blocks"
