require "../members"

module Emerald
  class TypeChecker
    private def check_concurrency_instance_method(expr : AST::MethodCall, receiver_type : String, scope : Scope) : String?
      if receiver_type.starts_with?("Fiber<") || receiver_type.starts_with?("Thread<") || receiver_type.starts_with?("VirtualThread<")
        case expr.name
        when "await"
          unless expr.args.empty?
            wrong_arg = expr.args[0]

            raise TypeError.new(
              "await() takes no arguments",
              wrong_arg.line,
              wrong_arg.col,
              "Use #{method_call_receiver_name(expr)}.await() without arguments to wait for the #{receiver_type} result",
              expression_marker_length(wrong_arg))
          end
          inner = receiver_type[(receiver_type.index("<").not_nil! + 1)..-2]
          return inner
        end
      elsif receiver_type == "Mutex"
        case expr.name
        when "lock", "unlock"
          unless expr.args.empty?
            raise TypeError.new("#{expr.name}() takes no arguments", expr.line, expr.col)
          end
          return "Void"
        when "synchronize"
          unless expr.args.size == 1
            raise TypeError.new("synchronize requires 1 lambda argument", expr.line, expr.col)
          end
          arg_type = check_expr(expr.args[0], scope)
          unless arg_type.starts_with?("Fn(")
            raise TypeError.new("synchronize requires a lambda", expr.line, expr.col)
          end
          _params, ret = TypeSystem.parse_fn_type_string(arg_type)
          return ret
        end
      elsif receiver_type.starts_with?("Channel<")
        inner = receiver_type[(receiver_type.index("<").not_nil! + 1)..-2]
        case expr.name
        when "send"
          unless expr.args.size == 1
            raise TypeError.new("send requires 1 argument", expr.line, expr.col)
          end
          send_arg = expr.args[0]
          actual = check_expr(send_arg, scope)
          if inner != "?"
            unless types_compatible?(inner, actual)
              raise TypeError.new(
                "cannot send #{actual} into Channel<#{inner}> (send: expected #{inner}, got #{actual})",
                send_arg.line,
                send_arg.col,
                "Send a value compatible with #{inner} or change the channel type to Channel<#{actual}>",
                expression_marker_length(send_arg))
            end
          end
          return "Void"
        when "receive"
          unless expr.args.empty?
            raise TypeError.new("receive() takes no arguments", expr.line, expr.col)
          end
          return inner
        when "close"
          return "Void"
        end
      end
      nil
    end

  end
end
