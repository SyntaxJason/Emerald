require "../type_checker"

module Emerald
  class TypeChecker
    private def expression_marker_length(expr : AST::Node) : Int32
      case expr
      when AST::StringLiteral
        expr.value.size + 2
      when AST::IntLiteral
        expr.value.to_s.size
      when AST::FloatLiteral
        expr.value.to_s.size
      when AST::BoolLiteral
        expr.value.to_s.size
      when AST::Identifier
        expr.name.size
      when AST::CallExpr
        expr.callee.size
      when AST::MethodCall
        expr.name.size
      when AST::MemberAccess
        expr.name.size
      else
        1
      end
    end

    private def marker_length_for_type(type_name : String) : Int32
      length = type_name.size
      return 1 if length <= 0
      return 80 if length > 80

      length
    end

    private def initialization_hint(name : String, expected : String, actual : String) : String?
      if spawn_handle_type?(expected) && spawn_handle_type?(actual)
        expected_inner = generic_inner_type(expected)
        return "The last expression inside the spawn block becomes the task result. Return #{expected_inner} or change '#{name}' to #{actual}"
      end

      if expected.starts_with?("Channel<") && actual.starts_with?("Channel<")
        return "Use a matching Channel<T> type on both sides"
      end

      "Use a value compatible with #{expected} or change the declared type to #{actual}"
    end

    private def spawn_handle_type?(type_name : String) : Bool
      type_name.starts_with?("Fiber<") ||
        type_name.starts_with?("Thread<") ||
        type_name.starts_with?("VirtualThread<")
    end

    private def generic_inner_type(type_name : String) : String
      start = type_name.index("<")
      return "?" unless start

      type_name[(start.not_nil! + 1)..-2]
    end

    private def method_call_receiver_name(expr : AST::MethodCall) : String
      receiver = expr.receiver

      if receiver.is_a?(AST::Identifier)
        return receiver.name
      end

      "task"
    end

    private def types_compatible?(expected : String, actual : String) : Bool
      return true if expected == actual
      return true if expected == "Any" || actual == "Any"
      return true if expected == "Float" && actual == "Int"

      if expected.starts_with?("Result<") && actual.starts_with?("Result<")
        e_inner = expected[7..-2]
        a_inner = actual[7..-2]
        e_parts = e_inner.split(",", 2)
        a_parts = a_inner.split(",", 2)
        if e_parts.size == 2 && a_parts.size == 2
          ok_match  = e_parts[0] == "?" || a_parts[0] == "?" || types_compatible?(e_parts[0], a_parts[0])
          err_match = e_parts[1] == "?" || a_parts[1] == "?" || types_compatible?(e_parts[1], a_parts[1])
          return ok_match && err_match
        end
      end

      if expected.starts_with?("Fn(") && actual.starts_with?("Fn(")
        return expected == actual
      end

      if expected.includes?("<") && actual.includes?("<")
        exp_lt = expected.index("<").not_nil!
        act_lt = actual.index("<").not_nil!
        if expected[0...exp_lt] == actual[0...act_lt]
          exp_args = expected[(exp_lt + 1)..-2]
          act_args = actual[(act_lt + 1)..-2]
          return true if exp_args == "?" || act_args == "?"
        end
      end

      if @resolver.registry[actual] && @resolver.registry[expected]
        return @resolver.registry.assignable?(actual, expected)
      end
      false
    end

    private def type_ref_to_fqn(ref : AST::TypeRef) : String
      case ref
      when AST::NamedType
        nt = ref.as(AST::NamedType)
        return nt.name if Resolver::BUILTIN_TYPES.includes?(nt.name)
        return nt.name if RESERVED_NAMES.includes?(nt.name)
        return nt.name if BUILTIN_CONTAINER_NAMES.includes?(nt.name)
        return nt.name if MACRO_AST_TYPES.includes?(nt.name)
        return nt.name if @current_type_params.includes?(nt.name)
        if nt.name.includes?("::")
          segments = nt.name.split("::")
          type_name = segments.pop
          return @resolver.namespace_resolver.resolve_type_qualified(segments, type_name, nt.line, nt.col)
        end
        @resolver.namespace_resolver.resolve_type_simple(nt.name, @current_namespace, nt.line, nt.col)
      when AST::GenericType
        gt = ref.as(AST::GenericType)
        base_fqn = if Resolver::BUILTIN_TYPES.includes?(gt.name) ||
                       RESERVED_NAMES.includes?(gt.name) ||
                       BUILTIN_CONTAINER_NAMES.includes?(gt.name) ||
                       @current_type_params.includes?(gt.name)
                     gt.name
                   else
                     if gt.name.includes?("::")
                       segments = gt.name.split("::")
                       type_name = segments.pop
                       @resolver.namespace_resolver.resolve_type_qualified(segments, type_name, gt.line, gt.col)
                     else
                       @resolver.namespace_resolver.resolve_type_simple(gt.name, @current_namespace, gt.line, gt.col)
                     end
                   end
        args = gt.type_args.map { |a| type_ref_to_fqn(a) }.join(",")
        "#{base_fqn}<#{args}>"
      when AST::FunctionType
        ft = ref.as(AST::FunctionType)
        params = ft.param_types.map { |p| type_ref_to_fqn(p) }.join(",")
        "Fn(#{params}):#{type_ref_to_fqn(ft.return_type)}"
      else
        "Unknown"
      end
    end

  end
end
