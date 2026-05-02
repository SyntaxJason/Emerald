require "./base"
require "./statements"
require "./expressions"

module Emerald
  class Parser
    def parse_top_level : AST::Node
      saved = @pos

      if peek.type == TokenType::KwAlias
        return parse_alias_decl
      end

      if peek.type == TokenType::KwMain
        return parse_main_decl
      end

      parse_visibility
      parse_mutability

      case peek.type
      when TokenType::KwClass
        @pos = saved
        return parse_class_decl(false, false)
      when TokenType::KwData
        @pos = saved
        return parse_class_decl(true, false)
      when TokenType::KwAbstract
        @pos = saved
        return parse_class_decl(false, true)
      when TokenType::KwInterface
        @pos = saved
        return parse_interface_decl
      end

      if peek.type.in?([TokenType::KwInt, TokenType::KwFloat, TokenType::KwBool,
                        TokenType::KwChar, TokenType::KwString, TokenType::KwVoid]) ||
         peek.type == TokenType::Identifier ||
         peek.type == TokenType::LParen
        skip_type
        if peek.type == TokenType::Identifier
          @pos += 1
          if peek.type == TokenType::LParen
            @pos = saved
            return parse_function_decl
          else
            @pos = saved
            return parse_var_decl_top
          end
        end
      end

      @pos = saved
      parse_statement
    end

    private def parse_var_decl_top : AST::VarDecl
      tok = peek
      mutability = parse_mutability
      type_ref = parse_type_ref
      name_tok = expect(TokenType::Identifier)
      expect(TokenType::Eq)
      init = parse_expression
      expect(TokenType::Semicolon)
      AST::VarDecl.new(mutability, type_ref, name_tok.value, init).at(tok.line, tok.col).as(AST::VarDecl)
    end

    private def parse_alias_decl : AST::AliasDecl
      tok = expect(TokenType::KwAlias)
      name = expect(TokenType::Identifier).value
      expect(TokenType::Eq)
      segments = [] of String
      segments << expect(TokenType::Identifier).value
      while peek.type == TokenType::ColonColon
        consume
        segments << expect(TokenType::Identifier).value
      end
      expect(TokenType::Semicolon)
      target = AST::QualifiedName.new(segments).at(tok.line, tok.col).as(AST::QualifiedName)
      AST::AliasDecl.new(name, target).at(tok.line, tok.col).as(AST::AliasDecl)
    end

    private def parse_main_decl : AST::MainDecl
      tok = expect(TokenType::KwMain)
      expect(TokenType::LParen)
      expect(TokenType::RParen)
      body = parse_block_expr
      AST::MainDecl.new(body).at(tok.line, tok.col).as(AST::MainDecl)
    end

    private def parse_function_decl : AST::FunctionDecl
      tok = peek
      vis = parse_visibility
      parse_mutability
      ret_type = parse_type_ref
      name_tok = expect(TokenType::Identifier)
      expect(TokenType::LParen)
      params = parse_params
      expect(TokenType::RParen)
      body = parse_block_expr
      AST::FunctionDecl.new(vis, name_tok.value, params, ret_type, body).at(tok.line, tok.col).as(AST::FunctionDecl)
    end

    private def parse_params : Array(AST::Param)
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
      params
    end

    private def parse_class_decl(is_data : Bool, is_abstract : Bool) : AST::ClassDecl
      start_tok = peek
      vis = parse_visibility
      parse_mutability
      expect(TokenType::KwAbstract) if is_abstract
      expect(TokenType::KwData) if is_data
      expect(TokenType::KwClass)
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

      data_params = [] of AST::FieldDecl
      if is_data && peek.type == TokenType::LParen
        consume
        unless peek.type == TokenType::RParen
          loop do
            field_vis = AST::Visibility::Public
            if peek.type == TokenType::At
              consume
              vis_tok = consume
              field_vis = case vis_tok.value
                          when "public"    then AST::Visibility::Public
                          when "private"   then AST::Visibility::Private
                          when "protected" then AST::Visibility::Protected
                          when "internal"  then AST::Visibility::Internal
                          else
                            raise ParseError.new("Unknown visibility annotation '@#{vis_tok.value}'", vis_tok.line, vis_tok.col)
                          end
            end
            ftype = parse_type_ref
            fname = expect(TokenType::Identifier)
            data_params << AST::FieldDecl.new(field_vis, AST::Mutability::Mutable, ftype, fname.value, nil)
              .at(fname.line, fname.col).as(AST::FieldDecl)
            break unless peek.type == TokenType::Comma
            consume
          end
        end
        expect(TokenType::RParen)
      end

      base : String? = nil
      if peek.type == TokenType::KwExtends
        consume
        base = expect(TokenType::Identifier).value
      end

      interfaces = [] of String
      if peek.type == TokenType::KwImplements
        consume
        loop do
          interfaces << expect(TokenType::Identifier).value
          break unless peek.type == TokenType::Comma
          consume
        end
      end

      fields = [] of AST::FieldDecl
      methods = [] of AST::MethodDecl
      ctors = [] of AST::ConstructorDecl

      if is_data && peek.type != TokenType::LBrace
        return AST::ClassDecl.new(vis, name_tok.value, true, is_abstract, base, interfaces,
                                  data_params, methods, ctors, type_params)
          .at(start_tok.line, start_tok.col).as(AST::ClassDecl)
      end

      expect(TokenType::LBrace)
      while peek.type != TokenType::RBrace && !at_end?
        member = parse_class_member(name_tok.value)
        case member
        when AST::FieldDecl       then fields << member
        when AST::MethodDecl      then methods << member
        when AST::ConstructorDecl then ctors << member
        end
      end
      expect(TokenType::RBrace)

      fields = data_params + fields if is_data

      AST::ClassDecl.new(vis, name_tok.value, is_data, is_abstract, base, interfaces,
                        fields, methods, ctors, type_params)
        .at(start_tok.line, start_tok.col).as(AST::ClassDecl)
    end

    private def parse_class_member(class_name : String) : AST::Node
      start_tok = peek
      is_override = false
      while peek.type == TokenType::At
        consume
        ann_tok = expect(TokenType::Identifier)
        is_override = true if ann_tok.value == "override"
      end
      vis = parse_visibility
      mutability = parse_mutability
      is_abstract_method = false
      if peek.type == TokenType::KwAbstract
        consume
        is_abstract_method = true
      end

      if peek.type == TokenType::Identifier && peek.value == class_name &&
         peek_at(@pos + 1).try(&.type) == TokenType::LParen
        return parse_constructor(vis, class_name)
      end

      ret_or_field_type = parse_type_ref
      name_tok = expect(TokenType::Identifier)

      if peek.type == TokenType::LParen
        consume
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

        AST::MethodDecl.new(vis, name_tok.value, params, ret_or_field_type, body,
                            is_override, false, is_abstract_method)
          .at(start_tok.line, start_tok.col).as(AST::MethodDecl)
      else
        init : AST::Node? = nil
        if peek.type == TokenType::Eq
          consume
          init = parse_expression
        end
        expect(TokenType::Semicolon)
        AST::FieldDecl.new(vis, mutability, ret_or_field_type, name_tok.value, init)
          .at(start_tok.line, start_tok.col).as(AST::FieldDecl)
      end
    end

    private def parse_constructor(vis : AST::Visibility, class_name : String) : AST::ConstructorDecl
      start_tok = peek
      consume
      expect(TokenType::LParen)
      params = parse_params
      expect(TokenType::RParen)
      body = parse_block_expr
      AST::ConstructorDecl.new(vis, params, body)
        .at(start_tok.line, start_tok.col).as(AST::ConstructorDecl)
    end

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
          extends_ifaces << expect(TokenType::Identifier).value
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
