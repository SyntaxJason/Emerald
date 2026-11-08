require "../type_checker"

module Emerald
  class TypeChecker
    private def check_lambda(expr : AST::LambdaExpr, scope : Scope) : String
      unless expr.expected_type.empty?
        if signature = sam_signature_for_type(expr.expected_type)
          return check_lambda_as_sam(expr, scope, signature)
        end
      end

      lambda_scope = Scope.new(scope)
      expr.params.each do |p|
        lambda_scope.declare(p.name,
          VarSymbol.new(p.name, AST::Mutability::Mutable, type_ref_to_fqn(p.type_ref)),
          p.line, p.col)
      end
      ret_type = infer_lambda_body_type(expr, lambda_scope, nil)
      param_str = expr.params.map { |p| type_ref_to_fqn(p.type_ref) }.join(",")
      "Fn(#{param_str}):#{ret_type}"
    end

    private def check_lambda_as_sam(expr : AST::LambdaExpr, scope : Scope, signature : Tuple(String, Array(String), String)) : String
      param_types = signature[1]
      return_type = signature[2]

      unless expr.params.size == param_types.size
        raise TypeError.new(
          "Lambda for #{expr.expected_type} expects #{param_types.size} parameters, got #{expr.params.size}",
          expr.line, expr.col)
      end

      lambda_scope = Scope.new(scope)
      expr.params.each_with_index do |p, index|
        expected = param_types[index]
        declared = type_ref_to_fqn(p.type_ref)
        unless declared == "Any" || types_compatible?(expected, declared)
          raise TypeError.new("Lambda parameter #{index + 1}: expected #{expected}, got #{declared}",
            p.line, p.col)
        end

        p.type_ref = AST::NamedType.new(expected).at(p.line, p.col).as(AST::NamedType)
        lambda_scope.declare(p.name,
          VarSymbol.new(p.name, AST::Mutability::Mutable, expected),
          p.line, p.col)
      end

      actual_return = infer_lambda_body_type(expr, lambda_scope, return_type)
      unless types_compatible?(return_type, actual_return)
        raise TypeError.new("Lambda return type mismatch: expected #{return_type}, got #{actual_return}",
          expr.line, expr.col)
      end

      expr.expected_type
    end

    private def infer_lambda_body_type(expr : AST::LambdaExpr, lambda_scope : Scope, expected_return : String?) : String
      body = expr.body
      unless body.is_a?(AST::Block)
        return check_expr(body, lambda_scope)
      end

      block = body.as(AST::Block)
      saved_return = @current_function_return
      saved_lambda_return = @lambda_first_return_type
      @current_function_return = expected_return || "Any"
      @lambda_first_return_type = nil

      block.statements.each { |s| check_stmt(s, lambda_scope) }

      ret_type = if @lambda_first_return_type
                   @lambda_first_return_type.not_nil!
                 elsif !block.statements.empty? && block.statements.last.is_a?(AST::ExpressionStmt)
                   last_expr = block.statements.last.as(AST::ExpressionStmt).expression
                   check_expr(last_expr, lambda_scope)
                 else
                   "Void"
                 end

      @lambda_first_return_type = saved_lambda_return
      @current_function_return = saved_return
      ret_type
    end

    private def check_method_ref(expr : AST::MethodRef, scope : Scope) : String
      if tn = expr.type_name
        info = @resolver.registry[tn] || @resolver.registry[
          @resolver.namespace_resolver.resolve_type_simple(tn, @current_namespace, expr.line, expr.col)
        ]
        unless info
          raise TypeError.new("Unknown type '#{tn}' in method reference", expr.line, expr.col)
        end
        method_lookup = lookup_method_with_subs(info.fqn, expr.method_name)
        unless method_lookup
          raise TypeError.new("Type '#{tn}' has no method '#{expr.method_name}'", expr.line, expr.col)
        end
        m = method_lookup[0]
        subs = method_lookup[1]
        params = [info.fqn] + m.param_types.map { |param| apply_subs(param, subs) }
        "Fn(#{params.join(",")}):#{apply_subs(m.return_type, subs)}"
      elsif recv = expr.receiver
        recv_type = check_expr(recv, scope)
        method_lookup = lookup_method_with_subs(recv_type, expr.method_name)
        unless method_lookup
          raise TypeError.new("Type '#{recv_type}' has no method '#{expr.method_name}'", expr.line, expr.col)
        end
        m = method_lookup[0]
        subs = method_lookup[1]
        params = m.param_types.map { |param| apply_subs(param, subs) }
        "Fn(#{params.join(",")}):#{apply_subs(m.return_type, subs)}"
      else
        raise TypeError.new("Invalid method reference", expr.line, expr.col)
      end
    end

    private def sam_signature_for_type(type_name : String) : Tuple(String, Array(String), String)?
      methods = abstract_methods_with_subs(type_name)
      return nil unless methods.size == 1

      method = methods[0][0]
      subs = methods[0][1]
      params = method.param_types.map { |param| apply_subs(param, subs) }
      {method.name, params, apply_subs(method.return_type, subs)}
    end

    private def abstract_methods_with_subs(type_name : String) : Array(Tuple(MethodInfo, Hash(String, String)))
      normalized = normalize_registry_type_name(type_name)
      base, subs = base_type_and_subs(normalized)
      info = @resolver.registry[base]
      return [] of Tuple(MethodInfo, Hash(String, String)) unless info
      return [] of Tuple(MethodInfo, Hash(String, String)) unless info.is_interface

      result = [] of Tuple(MethodInfo, Hash(String, String))

      info.interfaces.each do |iface|
        parent_type = normalize_registry_type_name(apply_subs(iface, subs))
        abstract_methods_with_subs(parent_type).each do |entry|
          result << entry unless result.any? { |existing| existing[0].name == entry[0].name }
        end
      end

      info.methods.each_value do |method|
        next unless method.is_abstract

        result.reject! { |entry| entry[0].name == method.name }
        result << {method, subs}
      end

      result
    end

    private def lookup_method_with_subs(type_name : String, method_name : String) : Tuple(MethodInfo, Hash(String, String))?
      normalized = normalize_registry_type_name(type_name)
      base, subs = base_type_and_subs(normalized)
      info = @resolver.registry[base]
      return nil unless info

      if method = info.methods[method_name]?
        return {method, subs}
      end

      if parent = info.base
        parent_type = normalize_registry_type_name(apply_subs(parent, subs))
        if found = lookup_method_with_subs(parent_type, method_name)
          return found
        end
      end

      info.interfaces.each do |iface|
        iface_type = normalize_registry_type_name(apply_subs(iface, subs))
        if found = lookup_method_with_subs(iface_type, method_name)
          return found
        end
      end

      nil
    end

  end
end
