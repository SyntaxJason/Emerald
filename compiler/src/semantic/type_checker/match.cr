require "../type_checker"

module Emerald
  class TypeChecker
    private def check_match(expr : AST::MatchExpr, scope : Scope) : String
      subject_type = check_expr(expr.subject, scope)
      expr.subject_type = subject_type

      arm_types = [] of String
      expr.arms.each do |arm|
        arm_scope = Scope.new(scope)
        arm.patterns.each { |p| check_pattern(p, subject_type, arm_scope) }
        if guard = arm.guard
          gt = check_expr(guard, arm_scope)
          unless gt == "Bool"
            raise TypeError.new("Guard expression must be Bool, got #{gt}", arm.line, arm.col)
          end
        end
        body = arm.body
        if body.is_a?(AST::Block)
          block = body.as(AST::Block)
          saved = @current_function_return
          @current_function_return = "Any"
          @lambda_first_return_type = nil
          block.statements.each { |s| check_stmt(s, arm_scope) }
          arm_types << (@lambda_first_return_type || "Void")
          @lambda_first_return_type = nil
          @current_function_return = saved
        else
          arm_types << check_expr(body, arm_scope)
        end
      end

      return "Void" if arm_types.empty?
      result = arm_types[0]
      arm_types.each do |t|
        next if t == result
        if types_compatible?(result, t)
        elsif types_compatible?(t, result)
          result = t
        elsif result == "Void" || t == "Void"
          result = "Void"
        else
          if result.starts_with?("Result<") && t.starts_with?("Result<")
            result = TypeSystem.unify_result_types(result, t)
          else
            raise TypeError.new("Match arms have incompatible types: #{result} vs #{t}", expr.line, expr.col)
          end
        end
      end
      result
    end

    private def check_pattern(pat : AST::Pattern, subject_type : String, scope : Scope)
      case pat
      when AST::WildcardPattern, AST::NullPattern
      when AST::LiteralPattern
        lit_type = check_expr(pat.value, scope)
        unless types_compatible?(subject_type, lit_type) || types_compatible?(lit_type, subject_type)
          raise TypeError.new("Pattern type #{lit_type} doesn't match subject #{subject_type}", pat.line, pat.col)
        end
      when AST::RangePattern
        st = check_expr(pat.start, scope)
        et = check_expr(pat.finish, scope)
        unless st == "Int" && et == "Int"
          raise TypeError.new("Range pattern bounds must be Int", pat.line, pat.col)
        end
        unless subject_type == "Int"
          raise TypeError.new("Range pattern requires Int subject, got #{subject_type}", pat.line, pat.col)
        end
      when AST::TypePattern
        if b = pat.binding
          unless scope.symbols.has_key?(b)
            scope.declare(b, VarSymbol.new(b, AST::Mutability::Final, pat.type_name), pat.line, pat.col)
          else
            sym = scope.symbols[b]
            sym.as(VarSymbol).type_name = pat.type_name if sym.is_a?(VarSymbol)
          end
        end
      when AST::BindPattern
        unless scope.symbols.has_key?(pat.name)
          scope.declare(pat.name, VarSymbol.new(pat.name, AST::Mutability::Final, subject_type), pat.line, pat.col)
        else
          sym = scope.symbols[pat.name]
          sym.as(VarSymbol).type_name = subject_type if sym.is_a?(VarSymbol)
        end
      when AST::DestructurePattern
        case pat.type_name
        when "Ok"
          unless subject_type.starts_with?("Result<")
            raise TypeError.new("Ok-pattern requires Result subject, got #{subject_type}", pat.line, pat.col)
          end
          inner = TypeSystem.result_inner_ok_type(subject_type)
          unless pat.sub_patterns.size == 1
            raise TypeError.new("Ok-pattern takes exactly 1 sub-pattern", pat.line, pat.col)
          end
          check_pattern(pat.sub_patterns[0], inner, scope)
        when "Err"
          unless subject_type.starts_with?("Result<")
            raise TypeError.new("Err-pattern requires Result subject, got #{subject_type}", pat.line, pat.col)
          end
          inner = TypeSystem.result_inner_err_type(subject_type)
          unless pat.sub_patterns.size == 1
            raise TypeError.new("Err-pattern takes exactly 1 sub-pattern", pat.line, pat.col)
          end
          check_pattern(pat.sub_patterns[0], inner, scope)
        else
          info = @resolver.registry[pat.type_name] || @resolver.registry[
            @resolver.namespace_resolver.resolve_type_simple(pat.type_name, @current_namespace, pat.line, pat.col)
          ]
          unless info
            raise TypeError.new("Unknown type '#{pat.type_name}' in pattern", pat.line, pat.col)
          end
          unless info.is_data
            raise TypeError.new("Destructuring only works on data classes, '#{pat.type_name}' isn't one", pat.line, pat.col)
          end
          fields = info.fields.values.to_a
          unless pat.sub_patterns.size == fields.size
            raise TypeError.new(
              "Pattern #{pat.type_name}(...) expects #{fields.size} fields, got #{pat.sub_patterns.size}",
              pat.line, pat.col)
          end
          pat.sub_patterns.each_with_index do |sub, i|
            check_pattern(sub, fields[i].type_name, scope)
          end
          unless types_compatible?(subject_type, info.fqn)
            raise TypeError.new("Pattern #{pat.type_name} can't match subject of type #{subject_type}", pat.line, pat.col)
          end
        end
      end
    end

  end
end
