require "./base"
require "./types"

module Emerald
  class Parser
    def parse_statement : AST::Node
      case peek.type
      when TokenType::LBrace   then parse_block
      when TokenType::KwIf     then parse_if
      when TokenType::KwWhile  then parse_while
      when TokenType::KwFor    then parse_for
      when TokenType::KwReturn then parse_return
      when TokenType::KwBreak
        tok = consume; expect(TokenType::Semicolon)
        AST::BreakStmt.new.at(tok.line, tok.col)
      when TokenType::KwContinue
        tok = consume; expect(TokenType::Semicolon)
        AST::ContinueStmt.new.at(tok.line, tok.col)
      when TokenType::KwFinal, TokenType::KwCryo
        parse_var_decl_stmt
      else
        if looks_like_var_decl?
          parse_var_decl_stmt
        elsif peek.type == TokenType::Identifier && peek_at(@pos + 1).try(&.type) == TokenType::Eq
          parse_assignment
        else
          parse_expr_or_assign_stmt
        end
      end
    end

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

    private def parse_var_decl_stmt : AST::VarDecl
      tok = peek
      mutability = parse_mutability
      type_ref = parse_type_ref
      name_tok = expect(TokenType::Identifier)
      expect(TokenType::Eq)
      init = parse_expression
      expect(TokenType::Semicolon)
      AST::VarDecl.new(mutability, type_ref, name_tok.value, init).at(tok.line, tok.col).as(AST::VarDecl)
    end

    private def parse_assignment : AST::AssignStmt
      name_tok = expect(TokenType::Identifier)
      expect(TokenType::Eq)
      value = parse_expression
      expect(TokenType::Semicolon)
      AST::AssignStmt.new(name_tok.value, value).at(name_tok.line, name_tok.col).as(AST::AssignStmt)
    end

    private def parse_expr_or_assign_stmt : AST::Node
      tok = peek
      expr = parse_expression
      if peek.type == TokenType::Eq && expr.is_a?(AST::MemberAccess)
        consume
        value = parse_expression
        expect(TokenType::Semicolon)
        ma = expr.as(AST::MemberAccess)
        return AST::ExpressionStmt.new(
          AST::MemberAssign.new(ma.receiver, ma.name, value).at(tok.line, tok.col)
        ).at(tok.line, tok.col)
      end
      expect(TokenType::Semicolon)
      AST::ExpressionStmt.new(expr).at(tok.line, tok.col)
    end

    private def parse_block : AST::Block
      tok = expect(TokenType::LBrace)
      stmts = [] of AST::Node
      until peek.type == TokenType::RBrace || at_end?
        stmts << parse_statement
      end
      expect(TokenType::RBrace)
      AST::Block.new(stmts).at(tok.line, tok.col).as(AST::Block)
    end

    private def parse_if : AST::IfStmt
      tok = expect(TokenType::KwIf)
      expect(TokenType::LParen)
      cond = parse_expression
      expect(TokenType::RParen)
      then_branch = parse_block
      else_branch : AST::Node? = nil
      if peek.type == TokenType::KwElse
        consume
        if peek.type == TokenType::KwIf
          else_branch = parse_if
        else
          else_branch = parse_block
        end
      end
      AST::IfStmt.new(cond, then_branch, else_branch).at(tok.line, tok.col).as(AST::IfStmt)
    end

    private def parse_while : AST::WhileStmt
      tok = expect(TokenType::KwWhile)
      expect(TokenType::LParen)
      cond = parse_expression
      expect(TokenType::RParen)
      body = parse_block
      AST::WhileStmt.new(cond, body).at(tok.line, tok.col).as(AST::WhileStmt)
    end

    private def parse_for : AST::ForStmt
      tok = expect(TokenType::KwFor)
      expect(TokenType::LParen)
      var_tok = expect(TokenType::Identifier)
      expect(TokenType::KwIn)
      iter = parse_expression
      expect(TokenType::RParen)
      body = parse_block
      AST::ForStmt.new(var_tok.value, iter, body).at(tok.line, tok.col).as(AST::ForStmt)
    end

    private def parse_return : AST::ReturnStmt
      tok = expect(TokenType::KwReturn)
      value : AST::Node? = nil
      unless peek.type == TokenType::Semicolon
        value = parse_expression
      end
      expect(TokenType::Semicolon)
      AST::ReturnStmt.new(value).at(tok.line, tok.col).as(AST::ReturnStmt)
    end
  end
end
