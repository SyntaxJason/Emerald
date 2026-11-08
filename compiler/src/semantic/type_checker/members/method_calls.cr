require "../members"

module Emerald
  class TypeChecker
    private def check_method_call(expr : AST::MethodCall, scope : Scope) : String
      if expr.receiver.is_a?(AST::Identifier)
        recv_id = expr.receiver.as(AST::Identifier)

        if ret = check_static_stdlib_call(expr, recv_id.name, scope)
          return ret
        end

        sym = scope.lookup(recv_id.name)
        if sym.is_a?(TypeSymbol) && sym.as(TypeSymbol).kind == "builtin"
          return check_static_builtin_call(expr, recv_id.name, scope)
        end
      end

      receiver_type = check_expr(expr.receiver, scope)
      expr.receiver_type = receiver_type

      if conc_ret = check_concurrency_instance_method(expr, receiver_type, scope)
        return conc_ret
      end

      if methods = BuiltinMethods.for_type(receiver_type)
        m = methods[expr.name]?
        if m
          unless expr.args.size == m.param_types.size
            raise TypeError.new(
              "Method '#{expr.name}' on #{receiver_type} expects #{m.param_types.size} arguments, got #{expr.args.size}",
              expr.line, expr.col)
          end
          inferred_substitutions = {} of String => String
          expr.args.each_with_index do |arg, i|
            actual = check_expr(arg, scope)
            expected = m.param_types[i]
            if expected == "?"
              inferred_substitutions["?"] = actual
            elsif expected.includes?("?")
              expected = substitute_placeholders(expected, inferred_substitutions, actual)
            end
            unless types_compatible?(expected, actual) || expected.includes?("?")
              raise TypeError.new("Argument #{i + 1} of '#{expr.name}': expected #{expected}, got #{actual}",
                arg.line, arg.col)
            end
          end
          ret = m.return_type
          if ret.includes?("?")
            inferred_substitutions.each do |k, v|
              ret = ret.gsub("?", v)
            end
          end
          return ret
        end
        raise TypeError.new("Type #{receiver_type} has no method '#{expr.name}'", expr.line, expr.col)
      end

      method_lookup = lookup_method_with_subs(receiver_type, expr.name)
      unless method_lookup
        raise TypeError.new("Type #{receiver_type} has no method '#{expr.name}'", expr.line, expr.col)
      end
      m = method_lookup[0]
      subs = method_lookup[1]
      if dm = m.deprecated_message
        STDERR.puts "Warning: method '#{expr.name}' is deprecated: #{dm} (at #{expr.line}:#{expr.col})"
      end
      unless expr.args.size == m.param_types.size
        raise TypeError.new(
          "Method '#{expr.name}' expects #{m.param_types.size} arguments, got #{expr.args.size}",
          expr.line, expr.col)
      end
      expr.args.each_with_index do |arg, i|
        expected = apply_subs(m.param_types[i], subs)
        if arg.is_a?(AST::LambdaExpr)
          arg.as(AST::LambdaExpr).expected_type = expected
        end
        actual = check_expr(arg, scope)
        unless types_compatible?(expected, actual)
          raise TypeError.new("Argument #{i + 1} of '#{expr.name}': expected #{expected}, got #{actual}",
            arg.line, arg.col)
        end
      end
      apply_subs(m.return_type, subs)
    end

    private def substitute_placeholders(template : String, subs : Hash(String, String), latest : String) : String
      result = template
      subs.each do |k, v|
        result = result.gsub("?", v)
      end
      if result.includes?("?")
        result = result.gsub("?", latest)
      end
      result
    end

    private def check_static_stdlib_call(expr : AST::MethodCall, type_name : String, scope : Scope) : String?
      if intrinsic = RuntimeStaticIntrinsics.find(type_name, expr.name)
        check_static_intrinsic_args(expr, intrinsic, scope)
        return intrinsic.return_type
      end

      case {type_name, expr.name}
      when {"Duration", "millis"}
        check_static_int_args(expr, type_name, 1, scope)
        return static_stdlib_return_type(type_name)
      when {"Duration", "seconds"}
        check_static_int_args(expr, type_name, 1, scope)
        return static_stdlib_return_type(type_name)
      when {"Duration", "minutes"}
        check_static_int_args(expr, type_name, 1, scope)
        return static_stdlib_return_type(type_name)
      when {"Duration", "hours"}
        check_static_int_args(expr, type_name, 1, scope)
        return static_stdlib_return_type(type_name)
      when {"Duration", "days"}
        check_static_int_args(expr, type_name, 1, scope)
        return static_stdlib_return_type(type_name)
      when {"OffsetDateTime", "now"}
        check_static_int_args(expr, type_name, 0, scope)
        return static_stdlib_return_type(type_name)
      when {"OffsetDateTime", "utcNow"}
        check_static_int_args(expr, type_name, 0, scope)
        return static_stdlib_return_type(type_name)
      when {"OffsetDateTime", "of"}
        check_static_int_args(expr, type_name, 7, scope)
        return static_stdlib_return_type(type_name)
      when {"Console", "print"}
        check_static_any_args(expr, type_name, 1, scope)
        return "Void"
      when {"Console", "println"}
        check_static_any_args(expr, type_name, 1, scope)
        return "Void"
      when {"Console", "error"}
        check_static_any_args(expr, type_name, 1, scope)
        return "Void"
      when {"Console", "write"}
        check_static_string_args(expr, type_name, 1, scope)
        return "Void"
      when {"Console", "writeLine"}
        check_static_string_args(expr, type_name, 1, scope)
        return "Void"
      when {"Console", "errorLine"}
        check_static_string_args(expr, type_name, 1, scope)
        return "Void"
      when {"Console", "blankLine"}
        check_static_string_args(expr, type_name, 0, scope)
        return "Void"
      when {"Console", "readLine"}
        check_static_string_args(expr, type_name, 0, scope)
        return "String"
      when {"Console", "readLineOr"}
        check_static_string_args(expr, type_name, 1, scope)
        return "String"
      when {"Console", "tryReadLine"}
        check_static_string_args(expr, type_name, 0, scope)
        return "Std::Result::IResult<String,String>"
      when {"Console", "prompt"}
        check_static_string_args(expr, type_name, 1, scope)
        return "String"
      when {"Console", "promptOr"}
        check_static_string_args(expr, type_name, 2, scope)
        return "String"
      when {"Console", "confirm"}
        check_static_string_args(expr, type_name, 1, scope)
        return "Bool"
      when {"Console", "confirmOr"}
        check_static_arg_types(expr, type_name, ["String", "Bool"], scope)
        return "Bool"
      when {"Math", "abs"}
        check_static_int_args(expr, type_name, 1, scope)
        return "Int"
      when {"Math", "min"}
        check_static_int_args(expr, type_name, 2, scope)
        return "Int"
      when {"Math", "max"}
        check_static_int_args(expr, type_name, 2, scope)
        return "Int"
      when {"Math", "clamp"}
        check_static_int_args(expr, type_name, 3, scope)
        return "Int"
      when {"Path", "current"}
        check_static_string_args(expr, type_name, 0, scope)
        return static_stdlib_return_type(type_name)
      when {"Path", "join"}
        check_static_string_args(expr, type_name, 2, scope)
        return "String"
      when {"Path", "fileName"}
        check_static_string_args(expr, type_name, 1, scope)
        return "String"
      when {"Path", "extension"}
        check_static_string_args(expr, type_name, 1, scope)
        return "String"
      when {"Path", "parent"}
        check_static_string_args(expr, type_name, 1, scope)
        return "String"
      when {"File", "readText"}
        check_static_string_args(expr, type_name, 1, scope)
        return "String"
      when {"File", "readLines"}
        check_static_string_args(expr, type_name, 1, scope)
        return "List<String>"
      when {"File", "writeText"}
        check_static_string_args(expr, type_name, 2, scope)
        return "Void"
      when {"File", "appendText"}
        check_static_string_args(expr, type_name, 2, scope)
        return "Void"
      when {"File", "tryReadText"}
        check_static_string_args(expr, type_name, 1, scope)
        return "Std::Result::IResult<String,String>"
      when {"File", "tryWriteText"}
        check_static_string_args(expr, type_name, 2, scope)
        return "Std::Result::IResult<Bool,String>"
      when {"File", "tryAppendText"}
        check_static_string_args(expr, type_name, 2, scope)
        return "Std::Result::IResult<Bool,String>"
      when {"File", "exists"}
        check_static_string_args(expr, type_name, 1, scope)
        return "Bool"
      when {"File", "isFile"}
        check_static_string_args(expr, type_name, 1, scope)
        return "Bool"
      when {"File", "isDirectory"}
        check_static_string_args(expr, type_name, 1, scope)
        return "Bool"
      when {"File", "delete"}
        check_static_string_args(expr, type_name, 1, scope)
        return "Bool"
      when {"File", "size"}
        check_static_string_args(expr, type_name, 1, scope)
        return "Int"
      when {"Directory", "exists"}
        check_static_string_args(expr, type_name, 1, scope)
        return "Bool"
      when {"Directory", "create"}
        check_static_string_args(expr, type_name, 1, scope)
        return "Bool"
      when {"Directory", "delete"}
        check_static_string_args(expr, type_name, 1, scope)
        return "Bool"
      when {"Directory", "list"}
        check_static_string_args(expr, type_name, 1, scope)
        return "List<String>"
      when {"Http", "get"}
        check_static_string_args(expr, type_name, 1, scope)
        return "Std::Result::IResult<Std::Http::IHttpResponse,String>"
      when {"Http", "postText"}
        check_static_string_args(expr, type_name, 2, scope)
        return "Std::Result::IResult<Std::Http::IHttpResponse,String>"
      when {"Tcp", "connect"}
        check_static_arg_types(expr, type_name, ["String", "Int"], scope)
        return "Std::Result::IResult<Std::Net::ITcpConnection,String>"
      when {"Tcp", "listen"}
        check_static_arg_types(expr, type_name, ["String", "Int"], scope)
        return "Std::Result::IResult<Std::Net::ITcpListener,String>"
      when {"Tcp", "isOpen"}
        check_static_arg_types(expr, type_name, ["Int"], scope)
        return "Bool"
      when {"Tcp", "listenerIsOpen"}
        check_static_arg_types(expr, type_name, ["Int"], scope)
        return "Bool"
      when {"Tcp", "readText"}
        check_static_arg_types(expr, type_name, ["Int"], scope)
        return "String"
      when {"Tcp", "readLine"}
        check_static_arg_types(expr, type_name, ["Int"], scope)
        return "String"
      when {"Tcp", "tryReadText"}
        check_static_arg_types(expr, type_name, ["Int"], scope)
        return "Std::Result::IResult<String,String>"
      when {"Tcp", "tryReadLine"}
        check_static_arg_types(expr, type_name, ["Int"], scope)
        return "Std::Result::IResult<String,String>"
      when {"Tcp", "writeText"}
        check_static_arg_types(expr, type_name, ["Int", "String"], scope)
        return "Bool"
      when {"Tcp", "tryWriteText"}
        check_static_arg_types(expr, type_name, ["Int", "String"], scope)
        return "Std::Result::IResult<Bool,String>"
      when {"Tcp", "close"}
        check_static_arg_types(expr, type_name, ["Int"], scope)
        return "Bool"
      when {"Tcp", "tryClose"}
        check_static_arg_types(expr, type_name, ["Int"], scope)
        return "Std::Result::IResult<Bool,String>"
      when {"Tcp", "accept"}
        check_static_arg_types(expr, type_name, ["Int"], scope)
        return "Std::Result::IResult<Std::Net::ITcpConnection,String>"
      when {"Tcp", "closeListener"}
        check_static_arg_types(expr, type_name, ["Int"], scope)
        return "Bool"
      when {"Tcp", "tryCloseListener"}
        check_static_arg_types(expr, type_name, ["Int"], scope)
        return "Std::Result::IResult<Bool,String>"
      end

      nil
    end

    private def check_static_intrinsic_args(expr : AST::MethodCall, intrinsic : RuntimeStaticIntrinsic, scope : Scope)
      expected_types = intrinsic.param_types
      unless expr.args.size == expected_types.size
        raise TypeError.new(
          "#{intrinsic.receiver}.#{intrinsic.method_name} expects #{expected_types.size} arguments, got #{expr.args.size}",
          expr.line, expr.col)
      end

      expr.args.each_with_index do |arg, index|
        expected = expected_types[index]
        actual = check_expr(arg, scope)

        unless types_compatible?(expected, actual)
          raise TypeError.new(
            "Argument #{index + 1} of '#{intrinsic.receiver}.#{intrinsic.method_name}': expected #{expected}, got #{actual}",
            arg.line, arg.col)
        end
      end
    end

    private def check_static_any_args(expr : AST::MethodCall, type_name : String, count : Int32, scope : Scope)
      unless expr.args.size == count
        raise TypeError.new(
          "#{type_name}.#{expr.name} expects #{count} arguments, got #{expr.args.size}",
          expr.line, expr.col)
      end

      expr.args.each do |arg|
        check_expr(arg, scope)
      end
    end

    private def check_static_arg_types(expr : AST::MethodCall, type_name : String, expected_types : Array(String), scope : Scope)
      unless expr.args.size == expected_types.size
        raise TypeError.new(
          "#{type_name}.#{expr.name} expects #{expected_types.size} arguments, got #{expr.args.size}",
          expr.line, expr.col)
      end

      expr.args.each_with_index do |arg, index|
        expected = expected_types[index]
        actual = check_expr(arg, scope)

        unless types_compatible?(expected, actual)
          raise TypeError.new(
            "Argument #{index + 1} of '#{type_name}.#{expr.name}': expected #{expected}, got #{actual}",
            arg.line, arg.col)
        end
      end
    end

    private def check_static_string_args(expr : AST::MethodCall, type_name : String, count : Int32, scope : Scope)
      unless expr.args.size == count
        raise TypeError.new(
          "#{type_name}.#{expr.name} expects #{count} arguments, got #{expr.args.size}",
          expr.line, expr.col)
      end

      expr.args.each_with_index do |arg, index|
        actual = check_expr(arg, scope)

        unless actual == "String"
          raise TypeError.new(
            "Argument #{index + 1} of '#{type_name}.#{expr.name}': expected String, got #{actual}",
            arg.line, arg.col)
        end
      end
    end

    private def check_static_int_args(expr : AST::MethodCall, type_name : String, count : Int32, scope : Scope)
      unless expr.args.size == count
        raise TypeError.new(
          "#{type_name}.#{expr.name} expects #{count} arguments, got #{expr.args.size}",
          expr.line, expr.col)
      end

      expr.args.each_with_index do |arg, index|
        actual = check_expr(arg, scope)

        unless actual == "Int"
          raise TypeError.new(
            "Argument #{index + 1} of '#{type_name}.#{expr.name}': expected Int, got #{actual}",
            arg.line, arg.col)
        end
      end
    end

    private def static_stdlib_return_type(type_name : String) : String
      candidates = @resolver.registry.resolve_simple(type_name)

      candidates.empty? ? type_name : candidates.first
    end

    private def check_static_builtin_call(expr : AST::MethodCall, type_name : String, scope : Scope) : String
      if ret = check_static_stdlib_call(expr, type_name, scope)
        return ret
      end

      case {type_name, expr.name}
      when {"Fiber", "spawn"}, {"Thread", "spawn"}, {"VirtualThread", "spawn"}
        unless expr.args.size == 1
          raise TypeError.new("#{type_name}.spawn expects 1 lambda argument, got #{expr.args.size}",
            expr.line, expr.col)
        end
        arg_type = check_expr(expr.args[0], scope)
        unless arg_type.starts_with?("Fn(")
          raise TypeError.new("#{type_name}.spawn requires a lambda, got #{arg_type}",
            expr.line, expr.col)
        end
        params, ret = TypeSystem.parse_fn_type_string(arg_type)
        unless params.empty?
          raise TypeError.new("#{type_name}.spawn lambda must take no arguments",
            expr.line, expr.col)
        end
        expr.receiver_type = type_name
        return "#{type_name}<#{ret}>"
      when {"Mutex", "new"}
        unless expr.args.empty?
          raise TypeError.new("Mutex.new takes no arguments", expr.line, expr.col)
        end
        expr.receiver_type = "Mutex"
        return "Mutex"
      when {"Channel", "new"}
        unless expr.args.empty?
          raise TypeError.new("Channel.new takes no arguments", expr.line, expr.col)
        end
        result = expr.expected_type.empty? ? "Channel<?>" : expr.expected_type
        expr.receiver_type = result
        return result
      else
        raise TypeError.new("'#{type_name}' has no static method '#{expr.name}'",
          expr.line, expr.col)
      end
    end

  end
end
