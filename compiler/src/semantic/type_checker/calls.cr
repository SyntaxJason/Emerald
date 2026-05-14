require "../type_checker"

module Emerald
  class TypeChecker
    private def check_call(expr : AST::CallExpr, scope : Scope) : String
      raw = if expr.namespace_path.empty?
              scope.lookup(expr.callee) || @resolver.namespace_resolver.resolve_function_simple(expr.callee, @current_namespace, expr.line, expr.col)
            else
              @resolver.namespace_resolver.resolve_function_qualified(expr.namespace_path, expr.callee, expr.line, expr.col)
            end
      raise TypeError.new("Undefined function '#{expr.callee}'", expr.line, expr.col) unless raw

      if raw.is_a?(VarSymbol)
        var_type = raw.as(VarSymbol).type_name
        unless var_type.starts_with?("Fn(")
          raise TypeError.new("'#{expr.callee}' has type #{var_type}, not callable", expr.line, expr.col)
        end
        param_types, ret_type = TypeSystem.parse_fn_type_string(var_type)

        unless expr.args.size == param_types.size
          raise TypeError.new("'#{expr.callee}' expects #{param_types.size} arguments, got #{expr.args.size}",
            expr.line, expr.col)
        end
        expr.args.each_with_index do |arg, i|
          expected = param_types[i]
          if arg.is_a?(AST::LambdaExpr)
            arg.as(AST::LambdaExpr).expected_type = expected
          end
          actual = check_expr(arg, scope)
          unless types_compatible?(expected, actual)
            raise TypeError.new("Argument #{i + 1} of '#{expr.callee}': expected #{expected}, got #{actual}",
              arg.line, arg.col)
          end
        end
        return ret_type
      end

      sym = raw.as(FunctionSymbol)

      if sym.param_types == ["Any"]
        unless expr.args.size == 1
          raise TypeError.new("Function '#{expr.callee}' expects 1 argument, got #{expr.args.size}", expr.line, expr.col)
        end
        check_expr(expr.args[0], scope)
        return sym.return_type
      end

      unless expr.args.size == sym.param_types.size
        raise TypeError.new("Function '#{expr.callee}' expects #{sym.param_types.size} arguments, got #{expr.args.size}",
          expr.line, expr.col)
      end
      expr.args.each_with_index do |arg, i|
        expected = sym.param_types[i]
        if arg.is_a?(AST::LambdaExpr)
          arg.as(AST::LambdaExpr).expected_type = expected
        end
        actual = check_expr(arg, scope)
        unless types_compatible?(expected, actual)
          raise TypeError.new("Argument #{i + 1} of '#{expr.callee}': expected #{expected}, got #{actual}",
            arg.line, arg.col)
        end
      end
      sym.return_type
    end

    private def check_new(expr : AST::NewExpr, scope : Scope) : String
      if BUILTIN_CONTAINER_NAMES.includes?(expr.type_name)
        unless expr.args.empty?
          raise TypeError.new("#{expr.type_name}() constructor takes no arguments", expr.line, expr.col)
        end
        if expr.expected_type.empty?
          raise TypeError.new("Cannot infer type arguments for #{expr.type_name}(); declare the variable type explicitly",
            expr.line, expr.col)
        end
        return expr.expected_type
      end

      fqn = if expr.namespace_path.empty?
              @resolver.namespace_resolver.resolve_type_simple(expr.type_name, @current_namespace, expr.line, expr.col)
            else
              @resolver.namespace_resolver.resolve_type_qualified(expr.namespace_path, expr.type_name, expr.line, expr.col)
            end
      info = @resolver.registry[fqn].not_nil!
      expr.expected_type = fqn if expr.expected_type.empty?

      arg_types = expr.args.map { |a| check_expr(a, scope) }

      if !info.type_params.empty?
        if !expr.expected_type.empty?
          base, subs = base_type_and_subs(expr.expected_type)
          if base == fqn
            info.constructors.each do |ctor|
              next if ctor.param_types.size != arg_types.size
              all_match = true
              ctor.param_types.each_with_index do |pt, i|
                substituted = apply_subs(pt, subs)
                unless types_compatible?(substituted, arg_types[i])
                  all_match = false
                  break
                end
              end
              return expr.expected_type if all_match
            end
          end

          if inferred = infer_generic_new_from_expected(fqn, info, expr.expected_type, arg_types)
            expr.expected_type = inferred
            return inferred
          end
        end

        if inferred = infer_generic_new_from_constructor_args(fqn, info, arg_types)
          expr.expected_type = inferred
          return inferred
        end

        raise TypeError.new(
          "Cannot infer type arguments for generic #{fqn}; declare the variable type explicitly",
          expr.line, expr.col
        )
      end

      info.constructors.each do |ctor|
        next if ctor.param_types.size != arg_types.size
        all_match = true
        ctor.param_types.each_with_index do |pt, i|
          unless types_compatible?(pt, arg_types[i])
            all_match = false
            break
          end
        end
        if all_match
          expr.expected_type = fqn
          return fqn
        end
      end

      raise TypeError.new(
        "No matching constructor for #{fqn}(#{arg_types.join(", ")})",
        expr.line, expr.col
      )
    end

    private def infer_generic_new_from_expected(fqn : String, info : ClassInfo, expected_type : String, arg_types : Array(String)) : String?
      inferred = generic_instance_from_expected(fqn, info, expected_type)
      return nil unless inferred
      return nil unless generic_constructor_matches?(info, inferred, arg_types)

      inferred
    end

    private def infer_generic_new_from_constructor_args(fqn : String, info : ClassInfo, arg_types : Array(String)) : String?
      info.constructors.each do |ctor|
        next unless ctor.param_types.size == arg_types.size

        bindings = {} of String => String
        all_match = true

        ctor.param_types.each_with_index do |param_type, index|
          unless bind_type_template_to_expected(param_type, arg_types[index], info.type_params, bindings)
            all_match = false
            break
          end
        end

        next unless all_match

        if inferred = generic_instance_from_bindings(fqn, info, bindings)
          return inferred
        end
      end

      nil
    end

    private def generic_instance_from_expected(fqn : String, info : ClassInfo, expected_type : String) : String?
      normalized_expected = normalize_registry_type_name(expected_type)

      info.interfaces.each do |iface|
        bindings = {} of String => String
        next unless bind_generic_usage_to_expected(iface, normalized_expected, info.type_params, bindings)

        return generic_instance_from_bindings(fqn, info, bindings)
      end

      if base = info.base
        bindings = {} of String => String
        return generic_instance_from_bindings(fqn, info, bindings) if bind_generic_usage_to_expected(base, normalized_expected, info.type_params, bindings)
      end

      nil
    end

    private def generic_instance_from_bindings(fqn : String, info : ClassInfo, bindings : Hash(String, String)) : String?
      return nil unless info.type_params.all? { |param| bindings.has_key?(param) }

      args = info.type_params.map { |param| bindings[param] }
      "#{fqn}<#{args.join(",")}>"
    end

    private def bind_generic_usage_to_expected(usage : String, expected_type : String, class_type_params : Array(String), bindings : Hash(String, String)) : Bool
      normalized_usage = normalize_registry_type_name(usage)
      usage_base, usage_subs = base_type_and_subs(normalized_usage)
      expected_base, expected_subs = base_type_and_subs(expected_type)
      return false unless usage_base == expected_base

      usage_info = @resolver.registry[usage_base]
      return false unless usage_info

      usage_info.type_params.each do |param|
        template = usage_subs[param]? || param
        expected = expected_subs[param]? || param
        return false unless bind_type_template_to_expected(template, expected, class_type_params, bindings)
      end

      true
    end

    private def bind_type_template_to_expected(template : String, expected : String, class_type_params : Array(String), bindings : Hash(String, String)) : Bool
      if class_type_params.includes?(template)
        if existing = bindings[template]?
          return existing == expected
        end

        bindings[template] = expected
        return true
      end

      return true if template == expected

      normalized_template = normalize_registry_type_name(template)
      normalized_expected = normalize_registry_type_name(expected)
      return types_compatible?(normalized_template, normalized_expected) unless normalized_template.includes?("<") && normalized_expected.includes?("<")

      template_base, template_subs = base_type_and_subs(normalized_template)
      expected_base, expected_subs = base_type_and_subs(normalized_expected)
      return false unless template_base == expected_base

      template_info = @resolver.registry[template_base]
      return false unless template_info

      template_info.type_params.each do |param|
        template_arg = template_subs[param]? || param
        expected_arg = expected_subs[param]? || param
        return false unless bind_type_template_to_expected(template_arg, expected_arg, class_type_params, bindings)
      end

      true
    end

    private def generic_constructor_matches?(info : ClassInfo, instance_type : String, arg_types : Array(String)) : Bool
      _base, subs = base_type_and_subs(instance_type)

      info.constructors.each do |ctor|
        next unless ctor.param_types.size == arg_types.size

        all_match = true
        ctor.param_types.each_with_index do |param_type, index|
          substituted = apply_subs(param_type, subs)
          unless types_compatible?(substituted, arg_types[index])
            all_match = false
            break
          end
        end
        return true if all_match
      end

      false
    end

  end
end
