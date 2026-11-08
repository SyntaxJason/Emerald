require "../expressions"

module Emerald
  class Codegen
    private def emit_call(io : IO, expr : AST::CallExpr)
      sym = @resolver.global_scope.lookup(expr.callee)
      is_lambda_var = sym.is_a?(VarSymbol) && sym.as(VarSymbol).type_name.starts_with?("Fn(")

      target_fqn = if !expr.namespace_path.empty?
                     direct = "#{expr.namespace_path.join("::")}::#{expr.callee}"
                     if @resolver.namespace_resolver.functions_by_fqn.has_key?(direct)
                       direct
                     else
                       suffix = "::#{direct}"
                       match = @resolver.namespace_resolver.functions_by_fqn.keys.find { |k| k.ends_with?(suffix) }
                       match || direct
                     end
                   elsif fn_sym = @resolver.namespace_resolver.functions_by_fqn.values.find { |f| f.name == expr.callee }
                     fn_sym.fqn
                   else
                     expr.callee
                   end

      if !is_lambda_var && (bf = BuiltinFunctions.for_fqn(target_fqn))
        arg_strs = expr.args.map do |arg|
          String.build { |sb| emit_expr(sb, arg) }
        end
        template = bf.crystal_template
        arg_strs.each_with_index do |a, i|
          template = template.gsub("%a#{i}%", a)
        end
        io << template
        return
      end

      name = case expr.callee
             when "println" then "puts"
             when "print"   then "print"
             else
               if target_fqn != expr.callee
                 mangle_fn_fqn(target_fqn)
               else
                 expr.callee
               end
             end
      io << name
      io << ".call" if is_lambda_var
      io << "("
      expr.args.each_with_index do |arg, i|
        io << ", " if i > 0
        emit_expr(io, arg)
      end
      io << ")"
    end

    private def emit_new(io : IO, expr : AST::NewExpr)
      if BUILTIN_CONTAINER_NAMES.includes?(expr.type_name)
        ct = crystal_type(expr.expected_type)
        io << ct << ".new"
        return
      end

      fqn = if !expr.expected_type.empty?
              base_type_name(expr.expected_type)
            elsif expr.namespace_path.empty?
              candidates = @resolver.registry.resolve_simple(expr.type_name)
              candidates.empty? ? expr.type_name : candidates.first
            else
              "#{expr.namespace_path.join("::")}::#{expr.type_name}"
            end

      info = @resolver.registry[fqn]
      if info && !info.type_params.empty?
        ct = if !expr.expected_type.empty?
               crystal_type(expr.expected_type)
             else
               crystal_type(fqn)
             end
        io << ct << ".new("
      else
        io << mangle_fqn(fqn) << ".new("
      end
      expr.args.each_with_index do |arg, i|
        io << ", " if i > 0
        emit_expr(io, arg)
      end
      io << ")"
    end

    private def base_type_name(type_name : String) : String
      return type_name unless type_name.includes?("<") && type_name.ends_with?(">")

      type_name[0...type_name.index("<").not_nil!]
    end

  end
end
