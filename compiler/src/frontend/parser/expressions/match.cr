require "../expressions"

module Emerald
  class Parser
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

  end
end
