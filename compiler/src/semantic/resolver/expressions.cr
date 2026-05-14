require "../resolver"

module Emerald
  class Resolver
    private def resolve_expr(expr : AST::Node, scope : Scope)
      case expr
      when AST::Identifier
        if expr.namespace_path.empty?
          sym = scope.lookup(expr.name)
          unless sym
            raise ResolveError.new("Undefined identifier '#{expr.name}'", expr.line, expr.col)
          end
        end
      when AST::CallExpr
        if expr.namespace_path.empty?
          sym = scope.lookup(expr.callee) || @namespace_resolver.resolve_function_simple(expr.callee, @current_namespace, expr.line, expr.col)
          unless sym
            raise ResolveError.new("Undefined function '#{expr.callee}'", expr.line, expr.col)
          end
        else
          @namespace_resolver.resolve_function_qualified(expr.namespace_path, expr.callee, expr.line, expr.col) ||
            raise(ResolveError.new("Undefined function '#{expr.namespace_path.join("::")}::#{expr.callee}'", expr.line, expr.col))
        end
        expr.args.each { |a| resolve_expr(a, scope) }
      when AST::MethodCall
        if expr.receiver.is_a?(AST::Identifier) && static_stdlib_receiver?(expr.receiver.as(AST::Identifier).name)
          expr.args.each { |a| resolve_expr(a, scope) }
        else
          resolve_expr(expr.receiver, scope)
          expr.args.each { |a| resolve_expr(a, scope) }
        end
      when AST::MemberAccess
        resolve_expr(expr.receiver, scope)
      when AST::MemberAssign
        resolve_expr(expr.receiver, scope)
        resolve_expr(expr.value, scope)
      when AST::ThisExpr
        unless scope.lookup("this")
          raise ResolveError.new("'this' used outside of a method or constructor", expr.line, expr.col)
        end
      when AST::NewExpr
        if BUILTIN_CONTAINER_NAMES.includes?(expr.type_name)
          expr.args.each { |a| resolve_expr(a, scope) }
        else
          fqn = if expr.namespace_path.empty?
                  @namespace_resolver.resolve_type_simple(expr.type_name, @current_namespace, expr.line, expr.col)
                else
                  @namespace_resolver.resolve_type_qualified(expr.namespace_path, expr.type_name, expr.line, expr.col)
                end
          info = @registry[fqn].not_nil!
          if info.is_interface
            raise ResolveError.new("Cannot construct interface '#{expr.type_name}'", expr.line, expr.col)
          end
          if info.is_abstract
            raise ResolveError.new("Cannot construct abstract class '#{expr.type_name}'", expr.line, expr.col)
          end
          expr.args.each { |a| resolve_expr(a, scope) }
        end
      when AST::BinaryOp
        resolve_expr(expr.left, scope)
        resolve_expr(expr.right, scope)
      when AST::UnaryOp
        resolve_expr(expr.operand, scope)
      when AST::QuoteExpr
      when AST::UnquoteExpr
        resolve_expr(expr.expression, scope)
      when AST::RangeExpr
        resolve_expr(expr.start, scope)
        resolve_expr(expr.finish, scope)
      when AST::StringInterp
        expr.parts.each do |part|
          if part.is_a?(AST::InterpExpr)
            resolve_expr(part.as(AST::InterpExpr).expression, scope)
          end
        end
      when AST::OkExpr
        resolve_expr(expr.value, scope)
      when AST::ErrExpr
        resolve_expr(expr.value, scope)
      when AST::ListLiteral
        expr.elements.each { |e| resolve_expr(e, scope) }
      when AST::IndexExpr
        resolve_expr(expr.receiver, scope)
        resolve_expr(expr.index, scope)
      when AST::LambdaExpr
        lambda_scope = Scope.new(scope)
        expr.params.each do |p|
          lambda_scope.declare(p.name,
            VarSymbol.new(p.name, AST::Mutability::Mutable, type_ref_to_fqn(p.type_ref, @current_namespace)),
            p.line, p.col)
        end
        body = expr.body
        if body.is_a?(AST::Block)
          body.as(AST::Block).statements.each { |s| resolve_stmt(s, lambda_scope) }
        else
          resolve_expr(body, lambda_scope)
        end
      when AST::MethodRef
        if recv = expr.receiver
          resolve_expr(recv, scope)
        end
      when AST::MatchExpr
        resolve_expr(expr.subject, scope)
        expr.arms.each do |arm|
          arm_scope = Scope.new(scope)
          arm.patterns.each { |p| bind_pattern(p, arm_scope) }
          if guard = arm.guard
            resolve_expr(guard, arm_scope)
          end
          body = arm.body
          if body.is_a?(AST::Block)
            body.as(AST::Block).statements.each { |s| resolve_stmt(s, arm_scope) }
          else
            resolve_expr(body, arm_scope)
          end
        end
      end
    end

    private def static_stdlib_receiver?(name : String) : Bool
      name == "Console" ||
        name == "Math" ||
        name == "Duration" ||
        name == "OffsetDateTime" ||
        name == "Path" ||
        name == "File" ||
        name == "Directory"
    end

    private def bind_pattern(pat : AST::Pattern, scope : Scope)
      case pat
      when AST::WildcardPattern, AST::NullPattern, AST::LiteralPattern, AST::RangePattern
      when AST::TypePattern
        if b = pat.binding
          scope.declare(b,
            VarSymbol.new(b, AST::Mutability::Final, pat.type_name),
            pat.line, pat.col)
        end
      when AST::BindPattern
        scope.declare(pat.name,
          VarSymbol.new(pat.name, AST::Mutability::Final, "?"),
          pat.line, pat.col)
      when AST::DestructurePattern
        pat.sub_patterns.each { |sub| bind_pattern(sub, scope) }
      end
    end

  end
end
