require "../statements"

module Emerald
  class Parser
    def looks_like_var_decl? : Bool
      builtin_types = [TokenType::KwInt, TokenType::KwFloat, TokenType::KwBool,
                       TokenType::KwChar, TokenType::KwString]
      return true if builtin_types.includes?(peek.type) &&
                     peek_at(@pos + 1).try(&.type) == TokenType::Identifier
      if peek.type == TokenType::Identifier && peek.value[0].uppercase? &&
         peek_at(@pos + 1).try(&.type) == TokenType::Identifier
        return true
      end
      if peek.type == TokenType::Identifier && peek.value[0].uppercase? &&
         peek_at(@pos + 1).try(&.type) == TokenType::Lt
        return looks_like_generic_var_decl?
      end
      if peek.type == TokenType::Identifier && peek.value[0].uppercase? &&
         peek_at(@pos + 1).try(&.type) == TokenType::ColonColon
        return looks_like_qualified_var_decl?
      end
      if peek.type == TokenType::LParen && looks_like_fn_type?
        return looks_like_fn_var_decl?
      end
      false
    end

    private def looks_like_generic_var_decl? : Bool
      i = @pos + 1
      depth = 0
      while i < @tokens.size
        t = @tokens[i].type
        case t
        when TokenType::Lt then depth += 1
        when TokenType::Gt
          depth -= 1
          if depth == 0
            return @tokens[i + 1]?.try(&.type) == TokenType::Identifier
          end
        when TokenType::Semicolon, TokenType::LBrace, TokenType::EOF
          return false
        end
        i += 1
      end
      false
    end

    private def looks_like_qualified_var_decl? : Bool
      i = @pos
      while i < @tokens.size && @tokens[i].type == TokenType::Identifier &&
            @tokens[i + 1]?.try(&.type) == TokenType::ColonColon
        i += 2
      end
      if i < @tokens.size && @tokens[i].type == TokenType::Identifier &&
         @tokens[i + 1]?.try(&.type) == TokenType::Lt
        depth = 1
        i += 2
        while i < @tokens.size && depth > 0
          t = @tokens[i].type
          case t
          when TokenType::Lt then depth += 1
          when TokenType::Gt then depth -= 1
          when TokenType::Semicolon, TokenType::LBrace, TokenType::EOF then return false
          end
          i += 1
        end
      end
      i += 1 if i < @tokens.size && @tokens[i].type == TokenType::Identifier
      @tokens[i]?.try(&.type) == TokenType::Identifier &&
        (@tokens[i + 1]?.try(&.type) == TokenType::Eq ||
         @tokens[i + 1]?.try(&.type) == TokenType::Semicolon)
    end

    private def looks_like_fn_var_decl? : Bool
      depth = 1
      i = @pos + 1
      while i < @tokens.size && depth > 0
        t = @tokens[i].type
        case t
        when TokenType::LParen then depth += 1
        when TokenType::RParen
          depth -= 1
          break if depth == 0
        end
        i += 1
      end
      return false unless @tokens[i + 1]?.try(&.type) == TokenType::Arrow
      j = i + 2
      if @tokens[j]?.try(&.type) == TokenType::LParen
        rdepth = 1
        j += 1
        while j < @tokens.size && rdepth > 0
          t = @tokens[j].type
          case t
          when TokenType::LParen then rdepth += 1
          when TokenType::RParen
            rdepth -= 1
            break if rdepth == 0
          end
          j += 1
        end
        j += 1
        return false unless @tokens[j]?.try(&.type) == TokenType::Arrow
        j += 1
      end
      return false unless is_type_start?(@tokens[j]?.try(&.type))
      j += 1
      if @tokens[j]?.try(&.type) == TokenType::Lt
        gdepth = 1
        j += 1
        while j < @tokens.size && gdepth > 0
          t = @tokens[j].type
          case t
          when TokenType::Lt then gdepth += 1
          when TokenType::Gt
            gdepth -= 1
            break if gdepth == 0
          end
          j += 1
        end
        j += 1
      end
      @tokens[j]?.try(&.type) == TokenType::Identifier
    end

  end
end
