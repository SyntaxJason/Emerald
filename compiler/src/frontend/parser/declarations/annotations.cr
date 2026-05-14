require "../declarations"

module Emerald
  class Parser
    private def parse_annotation_args : Array(AST::Node)
      args = [] of AST::Node
      return args unless peek.type == TokenType::LParen
      consume
      unless peek.type == TokenType::RParen
        loop do
          args << parse_expression
          break unless peek.type == TokenType::Comma
          consume
        end
      end
      expect(TokenType::RParen)
      args
    end

  end
end
