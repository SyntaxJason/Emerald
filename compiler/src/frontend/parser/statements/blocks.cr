require "../statements"

module Emerald
  class Parser
    private def parse_block : AST::Block
      tok = expect(TokenType::LBrace)
      stmts = [] of AST::Node
      until peek.type == TokenType::RBrace || at_end?
        stmts << parse_statement
      end
      expect(TokenType::RBrace)
      AST::Block.new(stmts).at(tok.line, tok.col).as(AST::Block)
    end

    private def parse_if : AST::IfStmt
      tok = expect(TokenType::KwIf)
      expect(TokenType::LParen)
      cond = parse_expression
      expect(TokenType::RParen)
      then_branch = parse_block
      else_branch : AST::Node? = nil
      if peek.type == TokenType::KwElse
        consume
        if peek.type == TokenType::KwIf
          else_branch = parse_if
        else
          else_branch = parse_block
        end
      end
      AST::IfStmt.new(cond, then_branch, else_branch).at(tok.line, tok.col).as(AST::IfStmt)
    end

    private def parse_while : AST::WhileStmt
      tok = expect(TokenType::KwWhile)
      expect(TokenType::LParen)
      cond = parse_expression
      expect(TokenType::RParen)
      body = parse_block
      AST::WhileStmt.new(cond, body).at(tok.line, tok.col).as(AST::WhileStmt)
    end

    private def parse_for : AST::ForStmt
      tok = expect(TokenType::KwFor)
      expect(TokenType::LParen)
      var_tok = expect(TokenType::Identifier)
      expect(TokenType::KwIn)
      iter = parse_expression
      expect(TokenType::RParen)
      body = parse_block
      AST::ForStmt.new(var_tok.value, iter, body).at(tok.line, tok.col).as(AST::ForStmt)
    end

    private def parse_return : AST::ReturnStmt
      tok = expect(TokenType::KwReturn)
      value : AST::Node? = nil
      unless peek.type == TokenType::Semicolon
        value = parse_expression
      end
      expect(TokenType::Semicolon)
      AST::ReturnStmt.new(value).at(tok.line, tok.col).as(AST::ReturnStmt)
    end

  end
end
