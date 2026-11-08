require "../declarations"

module Emerald
  class Parser
    private def parse_interface_decl : AST::InterfaceDecl
      start_tok = peek
      vis = parse_visibility
      parse_mutability
      expect(TokenType::KwInterface)
      name_tok = expect(TokenType::Identifier)
      type_params = [] of String
      if peek.type == TokenType::Lt
        consume
        loop do
          type_params << expect(TokenType::Identifier).value
          break unless peek.type == TokenType::Comma
          consume
        end
        expect(TokenType::Gt)
      end
      extends_ifaces = [] of String
      if peek.type == TokenType::KwExtends
        consume
        loop do
          extends_ifaces << type_ref_to_source(parse_type_ref)
          break unless peek.type == TokenType::Comma
          consume
        end
      end
      methods = [] of AST::MethodDecl
      expect(TokenType::LBrace)
      while peek.type != TokenType::RBrace && !at_end?
        methods << parse_interface_method
      end
      expect(TokenType::RBrace)
      iface = AST::InterfaceDecl.new(vis, name_tok.value, extends_ifaces, methods)
        .at(start_tok.line, start_tok.col).as(AST::InterfaceDecl)
      iface.type_params = type_params
      iface
    end

    private def parse_interface_method : AST::MethodDecl
      start_tok = peek
      while peek.type == TokenType::At
        consume
        expect(TokenType::Identifier)
      end
      vis = parse_visibility
      is_default = false
      if peek.type == TokenType::KwDefault
        consume
        is_default = true
      end
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
      AST::MethodDecl.new(vis, name_tok.value, params, ret_type, body, false, is_default, false)
        .at(start_tok.line, start_tok.col).as(AST::MethodDecl)
    end

  end
end
