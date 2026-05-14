require "../declarations"

module Emerald
  class Parser
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
        base = parse_qualified_name_segments.join("::")
      end

      interfaces = [] of String
      if peek.type == TokenType::KwImplements
        consume
        loop do
          interfaces << type_ref_to_source(parse_type_ref)
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
      is_synchronized = false
      is_async = false
      deprecated_message : String? = nil
      user_annotations = [] of AST::Annotation
      while peek.type == TokenType::At
        consume
        ann_tok = expect(TokenType::Identifier)
        ann_args = parse_annotation_args
        case ann_tok.value
        when "override"
          is_override = true
        when "Override"
          is_override = true
        when "Synchronized"
          is_synchronized = true
        when "Async"
          is_async = true
        when "Deprecated"
          if ann_args.size == 1 && ann_args[0].is_a?(AST::StringLiteral)
            deprecated_message = ann_args[0].as(AST::StringLiteral).value
          else
            deprecated_message = "deprecated"
          end
        else
          ann = AST::Annotation.new(ann_tok.value, ann_args).at(ann_tok.line, ann_tok.col).as(AST::Annotation)
          user_annotations << ann
        end
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

        method = AST::MethodDecl.new(vis, name_tok.value, params, ret_or_field_type, body,
                            is_override, false, is_abstract_method)
          .at(start_tok.line, start_tok.col).as(AST::MethodDecl)
        method.is_synchronized = is_synchronized
        method.is_async = is_async
        method.deprecated_message = deprecated_message
        method.annotations = user_annotations
        method
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

  end
end
