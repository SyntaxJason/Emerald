require "../expressions"

module Emerald
  class Parser
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
