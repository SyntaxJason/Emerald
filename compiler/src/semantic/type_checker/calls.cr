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
          actual = check_expr(arg, scope)
          expected = param_types[i]
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
        actual = check_expr(arg, scope)
        expected = sym.param_types[i]
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
        end

        info.constructors.each do |ctor|
          next if ctor.param_types.size != arg_types.size
          subs = {} of String => String
          all_match = true
          ctor.param_types.each_with_index do |pt, i|
            if info.type_params.includes?(pt)
              if existing = subs[pt]?
                unless existing == arg_types[i]
                  all_match = false
                  break
                end
              else
                subs[pt] = arg_types[i]
              end
            else
              substituted = apply_subs(pt, subs)
              unless types_compatible?(substituted, arg_types[i])
                all_match = false
                break
              end
            end
          end
          if all_match && subs.size == info.type_params.size
            args_filled = info.type_params.map { |p| subs[p] }.join(",")
            return "#{fqn}<#{args_filled}>"
          end
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
        return fqn if all_match
      end

      raise TypeError.new(
        "No matching constructor for #{fqn}(#{arg_types.join(", ")})",
        expr.line, expr.col
      )
    end

  end
end
