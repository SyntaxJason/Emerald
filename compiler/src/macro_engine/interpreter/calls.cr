require "../interpreter"

module Emerald
  module MacroEngine
    class Interpreter
      private def eval_call(expr : AST::CallExpr) : MacroValue
        if !expr.namespace_path.empty?
          ns = expr.namespace_path.join("::")
          fqn = "#{ns}::#{expr.callee}"
          args = expr.args.map { |arg| eval_expr(arg) }
          return eval_static_builder(fqn, args)
        end

        raise "Macro error: unsupported function call '#{expr.callee}'"
      end

      private def eval_method_call(expr : AST::MethodCall) : MacroValue
        receiver = eval_expr(expr.receiver)
        args = expr.args.map { |a| eval_expr(a) }

        if receiver.is_a?(MacroASTRef)
          return eval_ast_method(receiver, expr.name, args)
        end

        if receiver.is_a?(MacroString)
          case expr.name
          when "+"
            if args.size == 1 && args[0].is_a?(MacroString)
              return MacroString.new(receiver.value + args[0].as(MacroString).value)
            end
          when "length"
            return MacroInt.new(receiver.value.size.to_i64)
          when "toString"
            return MacroString.new(receiver.value)
          end
        end

        if receiver.is_a?(MacroInt)
          case expr.name
          when "toInt"
            return MacroInt.new(receiver.value)
          when "toString"
            return MacroString.new(receiver.value.to_s)
          end
        end

        if receiver.is_a?(MacroFloat)
          case expr.name
          when "toInt"
            return MacroInt.new(receiver.value.to_i64)
          when "toString"
            return MacroString.new(receiver.value.to_s)
          end
        end

        if receiver.is_a?(MacroList)
          case expr.name
          when "add"
            if args.size == 1
              receiver.value << args[0]
              return MacroVoid.new
            end
          when "get"
            if args.size == 1 && args[0].is_a?(MacroInt)
              idx = args[0].as(MacroInt).value
              return receiver.value[idx] if idx < receiver.value.size
            end
          when "length"
            return MacroInt.new(receiver.value.size.to_i64)
          when "size"
            return MacroInt.new(receiver.value.size.to_i64)
          end
        end

        raise "Macro error: unsupported method '#{expr.name}' on #{receiver.class}"
      end

    end
  end
end
