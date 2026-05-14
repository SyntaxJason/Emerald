require "./base"

module Emerald
  class Parser
    def parse_type_ref : AST::TypeRef
      if peek.type == TokenType::LParen && looks_like_fn_type?
        return parse_fn_type
      end

      tok = consume
      name = case tok.type
             when TokenType::KwInt    then "Int"
             when TokenType::KwFloat  then "Float"
             when TokenType::KwBool   then "Bool"
             when TokenType::KwChar   then "Char"
             when TokenType::KwString then "String"
             when TokenType::KwVoid   then "Void"
             when TokenType::Identifier then tok.value
             else
               raise ParseError.new("Expected type, got #{tok.type} ('#{tok.value}')", tok.line, tok.col)
             end

      if tok.type == TokenType::Identifier
        segments = [name]
        while peek.type == TokenType::ColonColon
          consume
          segments << expect(TokenType::Identifier).value
        end
        name = segments.join("::")
      end

      base = AST::NamedType.new(name).at(tok.line, tok.col).as(AST::NamedType)

      if peek.type == TokenType::Lt && could_be_generic_args?
        consume
        args = [] of AST::TypeRef
        loop do
          args << parse_type_ref
          break unless peek.type == TokenType::Comma
          consume
        end
        expect(TokenType::Gt)
        return AST::GenericType.new(name, args).at(tok.line, tok.col).as(AST::GenericType)
      end

      base
    end

    def type_ref_to_source(ref : AST::TypeRef) : String
      case ref
      when AST::NamedType
        ref.name
      when AST::GenericType
        args = ref.type_args.map { |arg| type_ref_to_source(arg) }.join(",")
        "#{ref.name}<#{args}>"
      when AST::FunctionType
        params = ref.param_types.map { |param| type_ref_to_source(param) }.join(",")
        "Fn(#{params}):#{type_ref_to_source(ref.return_type)}"
      else
        "Unknown"
      end
    end

    def looks_like_fn_type? : Bool
      return false unless peek.type == TokenType::LParen
      depth = 1
      i = @pos + 1
      while i < @tokens.size && depth > 0
        t = @tokens[i].type
        case t
        when TokenType::LParen then depth += 1
        when TokenType::RParen
          depth -= 1
          if depth == 0
            return @tokens[i + 1]?.try(&.type) == TokenType::Arrow
          end
        end
        i += 1
      end
      false
    end

    private def parse_fn_type : AST::FunctionType
      start_tok = expect(TokenType::LParen)
      param_types = [] of AST::TypeRef
      unless peek.type == TokenType::RParen
        loop do
          param_types << parse_type_ref
          break unless peek.type == TokenType::Comma
          consume
        end
      end
      expect(TokenType::RParen)
      expect(TokenType::Arrow)
      ret = parse_type_ref
      AST::FunctionType.new(param_types, ret).at(start_tok.line, start_tok.col).as(AST::FunctionType)
    end

    def could_be_generic_args? : Bool
      return false unless peek.type == TokenType::Lt
      i = @pos + 1
      depth = 1
      while i < @tokens.size && depth > 0
        t = @tokens[i].type
        case t
        when TokenType::Lt then depth += 1
        when TokenType::Gt
          depth -= 1
          return true if depth == 0
        when TokenType::Semicolon, TokenType::LBrace, TokenType::EOF
          return false
        end
        i += 1
      end
      false
    end

    private def is_type_start?(t : TokenType?) : Bool
      return false unless t
      [TokenType::KwInt, TokenType::KwFloat, TokenType::KwBool,
       TokenType::KwChar, TokenType::KwString, TokenType::KwVoid,
       TokenType::Identifier].includes?(t)
    end

    def skip_type
      if peek.type == TokenType::LParen
        depth = 1
        consume
        while !at_end? && depth > 0
          t = peek.type
          case t
          when TokenType::LParen then depth += 1
          when TokenType::RParen then depth -= 1
          end
          consume
        end
        if peek.type == TokenType::Arrow
          consume
          skip_type
        end
        return
      end
      consume
      while peek.type == TokenType::ColonColon
        consume
        consume
      end
      if peek.type == TokenType::Lt
        depth = 1
        consume
        while !at_end? && depth > 0
          t = peek.type
          case t
          when TokenType::Lt then depth += 1
          when TokenType::Gt then depth -= 1
          end
          consume
        end
      end
    end
  end
end
