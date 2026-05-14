module Emerald
  class Parser
    def parse_top_level : AST::Node
      saved = @pos

      if peek.type == TokenType::KwUse
        return parse_use_decl
      end

      if peek.type == TokenType::KwAlias
        return parse_alias_decl
      end

      if peek.type == TokenType::KwMain
        return parse_main_decl
      end

      if peek.type == TokenType::KwMacro
        return parse_macro_decl
      end

      class_annotations = [] of AST::Annotation
      while peek.type == TokenType::At
        consume
        ann_tok = expect(TokenType::Identifier)
        ann_args = parse_annotation_args
        ann = AST::Annotation.new(ann_tok.value, ann_args).at(ann_tok.line, ann_tok.col).as(AST::Annotation)
        class_annotations << ann
      end

      saved_after_ann = @pos

      parse_visibility
      parse_mutability

      case peek.type
      when TokenType::KwClass
        @pos = saved_after_ann
        decl = parse_class_decl(false, false)
        decl.annotations = class_annotations
        return decl
      when TokenType::KwData
        @pos = saved_after_ann
        decl = parse_class_decl(true, false)
        decl.annotations = class_annotations
        return decl
      when TokenType::KwAbstract
        @pos = saved_after_ann
        decl = parse_class_decl(false, true)
        decl.annotations = class_annotations
        return decl
      when TokenType::KwInterface
        @pos = saved_after_ann
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

    private def parse_use_decl : AST::AliasDecl
      tok = expect(TokenType::KwUse)
      segments = parse_qualified_name_segments
      name = segments.last

      if peek.type == TokenType::KwAs
        consume
        name = expect(TokenType::Identifier).value
      end

      expect(TokenType::Semicolon)
      target = AST::QualifiedName.new(segments).at(tok.line, tok.col).as(AST::QualifiedName)
      AST::AliasDecl.new(name, target).at(tok.line, tok.col).as(AST::AliasDecl)
    end

    private def parse_alias_decl : AST::AliasDecl
      tok = expect(TokenType::KwAlias)
      name = expect(TokenType::Identifier).value
      expect(TokenType::Eq)
      segments = parse_qualified_name_segments
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

  end
end

require "./declarations/classes"
require "./declarations/interfaces"
require "./declarations/annotations"
require "./declarations/macros"
