require "../resolver"

module Emerald
  class Resolver
    private def resolve_block(block : AST::Block, parent : Scope)
      scope = Scope.new(parent)
      block.statements.each { |stmt| resolve_stmt(stmt, scope) }
    end

    private def resolve_stmt(stmt : AST::Node, scope : Scope)
      case stmt
      when AST::VarDecl
        resolve_var_decl(stmt, scope)
      when AST::AssignStmt
        sym = scope.lookup(stmt.target)
        unless sym
          raise ResolveError.new("Undefined variable '#{stmt.target}'", stmt.line, stmt.col)
        end
        unless sym.is_a?(VarSymbol)
          raise ResolveError.new("'#{stmt.target}' is not a variable", stmt.line, stmt.col)
        end
        if sym.as(VarSymbol).mutability != AST::Mutability::Mutable
          raise ResolveError.new("Cannot assign to '#{stmt.target}' (immutable)", stmt.line, stmt.col)
        end
        resolve_expr(stmt.value, scope)
      when AST::ExpressionStmt
        resolve_expr(stmt.expression, scope)
      when AST::ReturnStmt
        if v = stmt.value
          resolve_expr(v, scope)
        end
      when AST::IfStmt
        resolve_expr(stmt.condition, scope)
        resolve_block(stmt.then_branch, scope)
        if eb = stmt.else_branch
          case eb
          when AST::Block then resolve_block(eb, scope)
          when AST::IfStmt then resolve_stmt(eb, scope)
          end
        end
      when AST::WhileStmt
        resolve_expr(stmt.condition, scope)
        resolve_block(stmt.body, scope)
      when AST::ForStmt
        resolve_expr(stmt.iterable, scope)
        body_scope = Scope.new(scope)
        body_scope.declare(stmt.var_name,
          VarSymbol.new(stmt.var_name, AST::Mutability::Final, "Int"),
          stmt.line, stmt.col)
        stmt.body.statements.each { |s| resolve_stmt(s, body_scope) }
      when AST::Block
        resolve_block(stmt, scope)
      end
    end

    private def resolve_var_decl(decl : AST::VarDecl, scope : Scope)
      if init = decl.initializer
        resolve_expr(init, scope)
      end
      type_name = decl.type_ref ? type_ref_to_fqn(decl.type_ref.not_nil!, @current_namespace) : "?"
      scope.declare(decl.name,
        VarSymbol.new(decl.name, decl.mutability, type_name),
        decl.line, decl.col)
    end

  end
end
