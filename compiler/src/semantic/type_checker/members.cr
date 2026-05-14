require "../type_checker"

module Emerald
  class TypeChecker
    private def check_member_access(expr : AST::MemberAccess, scope : Scope) : String
      receiver_type = check_expr(expr.receiver, scope)
      base, subs = base_type_and_subs(receiver_type)
      info = @resolver.registry[base]
      unless info
        raise TypeError.new("Cannot access member '#{expr.name}' on type #{receiver_type}", expr.line, expr.col)
      end
      f = @resolver.registry.lookup_field(base, expr.name)
      if f
        return apply_subs(f.type_name, subs)
      end
      raise TypeError.new("Type #{receiver_type} has no field '#{expr.name}'", expr.line, expr.col)
    end

    private def check_member_assign(expr : AST::MemberAssign, scope : Scope) : String
      receiver_type = check_expr(expr.receiver, scope)
      base, subs = base_type_and_subs(receiver_type)
      info = @resolver.registry[base]
      unless info
        raise TypeError.new("Cannot assign to member of #{receiver_type}", expr.line, expr.col)
      end
      f = @resolver.registry.lookup_field(base, expr.name)
      unless f
        raise TypeError.new("Type #{receiver_type} has no field '#{expr.name}'", expr.line, expr.col)
      end
      field_type = apply_subs(f.type_name, subs)
      if expr.value.is_a?(AST::NewExpr)
        expr.value.as(AST::NewExpr).expected_type = field_type
      end
      if expr.value.is_a?(AST::LambdaExpr)
        expr.value.as(AST::LambdaExpr).expected_type = field_type
      end
      value_type = check_expr(expr.value, scope)
      unless types_compatible?(field_type, value_type)
        raise TypeError.new("Cannot assign #{value_type} to field '#{expr.name}' of type #{field_type}",
          expr.line, expr.col)
      end
      field_type
    end

  end
end

require "./members/method_calls"
require "./members/concurrency"
