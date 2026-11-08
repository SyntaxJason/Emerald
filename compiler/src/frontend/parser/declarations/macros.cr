require "../declarations"

module Emerald
  class Parser
    private def parse_macro_decl : AST::MacroDecl
      start_tok = expect(TokenType::KwMacro)
      name_tok = expect(TokenType::Identifier)
      expect(TokenType::KwOn)
      target_tok = expect(TokenType::Identifier)
      target = target_tok.value
      unless target == "Method" || target == "Class"
        raise ParseError.new("Macro target must be 'Method' or 'Class', got '#{target}'", target_tok.line, target_tok.col)
      end
      body = parse_block_expr
      AST::MacroDecl.new(name_tok.value, target, body).at(start_tok.line, start_tok.col).as(AST::MacroDecl)
    end

  end
end
