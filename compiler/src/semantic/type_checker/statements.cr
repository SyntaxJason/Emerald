require "../type_checker"

module Emerald
  class TypeChecker
    private def check_block(block : AST::Block, parent : Scope)
      scope = Scope.new(parent)
      block.statements.each { |s| check_stmt(s, scope) }
    end

    private def check_stmt(stmt : AST::Node, scope : Scope)
      case stmt
      when AST::VarDecl
        check_var_decl(stmt, scope)
      when AST::AssignStmt
        sym = scope.lookup(stmt.target).as(VarSymbol)
        if stmt.value.is_a?(AST::LambdaExpr)
          stmt.value.as(AST::LambdaExpr).expected_type = sym.type_name
        end
        value_type = check_expr(stmt.value, scope)
        unless types_compatible?(sym.type_name, value_type)
          raise TypeError.new("Cannot assign #{value_type} to '#{stmt.target}' of type #{sym.type_name}",
            stmt.line, stmt.col)
        end
      when AST::ExpressionStmt
        check_expr(stmt.expression, scope)
      when AST::ReturnStmt
        expected = @current_function_return || "Void"
        if v = stmt.value
          unless expected == "Any" || expected == "Void"
            if v.is_a?(AST::NewExpr)
              v.as(AST::NewExpr).expected_type = expected
            end
            if v.is_a?(AST::LambdaExpr)
              v.as(AST::LambdaExpr).expected_type = expected
            end
          end
          actual = check_expr(v, scope)
          if expected == "Any"
            @lambda_first_return_type ||= actual
          else
            unless types_compatible?(expected, actual)
              raise TypeError.new("Return type mismatch: expected #{expected}, got #{actual}", stmt.line, stmt.col)
            end
          end
        else
          if expected == "Any"
            @lambda_first_return_type ||= "Void"
          elsif expected != "Void"
            raise TypeError.new("Function returns #{expected} but got empty return", stmt.line, stmt.col)
          end
        end
      when AST::IfStmt
        cond_type = check_expr(stmt.condition, scope)
        unless cond_type == "Bool"
          raise TypeError.new("if-condition must be Bool, got #{cond_type}", stmt.line, stmt.col)
        end
        check_block(stmt.then_branch, scope)
        if eb = stmt.else_branch
          case eb
          when AST::Block then check_block(eb, scope)
          when AST::IfStmt then check_stmt(eb, scope)
          end
        end
      when AST::WhileStmt
        cond_type = check_expr(stmt.condition, scope)
        unless cond_type == "Bool"
          raise TypeError.new("while-condition must be Bool, got #{cond_type}", stmt.line, stmt.col)
        end
        check_block(stmt.body, scope)
      when AST::ForStmt
        iter_type = check_expr(stmt.iterable, scope)
        unless iter_type == "Range"
          raise TypeError.new("for-loop iterable must be Range, got #{iter_type}", stmt.line, stmt.col)
        end
        body_scope = Scope.new(scope)
        body_scope.declare(stmt.var_name,
          VarSymbol.new(stmt.var_name, AST::Mutability::Final, "Int"),
          stmt.line, stmt.col)
        stmt.body.statements.each { |s| check_stmt(s, body_scope) }
      when AST::Block
        check_block(stmt, scope)
      end
    end

    private def check_var_decl(decl : AST::VarDecl, scope : Scope)
      init = decl.initializer
      raise TypeError.new("Variable '#{decl.name}' must have an initializer", decl.line, decl.col) if init.nil?

      declared = decl.type_ref ? type_ref_to_fqn(decl.type_ref.not_nil!) : nil

      if declared && init.is_a?(AST::NewExpr)
        ne = init.as(AST::NewExpr)
        ne.expected_type = declared
      end

      if declared && init.is_a?(AST::LambdaExpr)
        init.as(AST::LambdaExpr).expected_type = declared
      end

      if declared && init.is_a?(AST::MethodCall)
        mc = init.as(AST::MethodCall)
        if mc.receiver.is_a?(AST::Identifier) && mc.name == "new"
          recv_name = mc.receiver.as(AST::Identifier).name
          if {"Channel", "Mutex"}.includes?(recv_name)
            mc.expected_type = declared
          end
        end
      end

      init_type = check_expr(init, scope)
      final_declared = declared || init_type
      unless types_compatible?(final_declared, init_type)
        raise TypeError.new(
          "Cannot initialize '#{decl.name}' (#{final_declared}) with #{init_type}",
          decl.line,
          decl.col,
          initialization_hint(decl.name, final_declared, init_type),
          marker_length_for_type(final_declared))
      end
      unless scope.symbols.has_key?(decl.name)
        scope.declare(decl.name,
          VarSymbol.new(decl.name, decl.mutability, final_declared),
          decl.line, decl.col)
      else
        sym = scope.symbols[decl.name]
        if sym.is_a?(VarSymbol)
          sym.as(VarSymbol).type_name = final_declared
        end
      end
    end

  end
end
