require "../type_checker"

module Emerald
  class TypeChecker
    private def check_lambda(expr : AST::LambdaExpr, scope : Scope) : String
      lambda_scope = Scope.new(scope)
      expr.params.each do |p|
        lambda_scope.declare(p.name,
          VarSymbol.new(p.name, AST::Mutability::Mutable, type_ref_to_fqn(p.type_ref)),
          p.line, p.col)
      end
      body = expr.body
      ret_type : String
      if body.is_a?(AST::Block)
        block = body.as(AST::Block)
        saved = @current_function_return
        @current_function_return = "Any"
        @lambda_first_return_type = nil
        block.statements.each { |s| check_stmt(s, lambda_scope) }
        if @lambda_first_return_type
          ret_type = @lambda_first_return_type.not_nil!
        elsif !block.statements.empty? && block.statements.last.is_a?(AST::ExpressionStmt)
          last_expr = block.statements.last.as(AST::ExpressionStmt).expression
          ret_type = check_expr(last_expr, lambda_scope)
        else
          ret_type = "Void"
        end
        @lambda_first_return_type = nil
        @current_function_return = saved
      else
        ret_type = check_expr(body, lambda_scope)
      end
      param_str = expr.params.map { |p| type_ref_to_fqn(p.type_ref) }.join(",")
      "Fn(#{param_str}):#{ret_type}"
    end

    private def check_method_ref(expr : AST::MethodRef, scope : Scope) : String
      if tn = expr.type_name
        info = @resolver.registry[tn] || @resolver.registry[
          @resolver.namespace_resolver.resolve_type_simple(tn, @current_namespace, expr.line, expr.col)
        ]
        unless info
          raise TypeError.new("Unknown type '#{tn}' in method reference", expr.line, expr.col)
        end
        m = @resolver.registry.lookup_method(info.fqn, expr.method_name)
        unless m
          raise TypeError.new("Type '#{tn}' has no method '#{expr.method_name}'", expr.line, expr.col)
        end
        params = [info.fqn] + m.param_types
        "Fn(#{params.join(",")}):#{m.return_type}"
      elsif recv = expr.receiver
        recv_type = check_expr(recv, scope)
        m = @resolver.registry.lookup_method(recv_type, expr.method_name)
        unless m
          raise TypeError.new("Type '#{recv_type}' has no method '#{expr.method_name}'", expr.line, expr.col)
        end
        "Fn(#{m.param_types.join(",")}):#{m.return_type}"
      else
        raise TypeError.new("Invalid method reference", expr.line, expr.col)
      end
    end

  end
end
