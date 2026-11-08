require "../interpreter"

module Emerald
  module MacroEngine
    class Interpreter
      private def eval_binary(op : String, left : MacroValue, right : MacroValue) : MacroValue
        case op
        when "+"
          if left.is_a?(MacroString) || right.is_a?(MacroString)
            MacroString.new(value_to_string(left) + value_to_string(right))
          elsif left.is_a?(MacroInt) && right.is_a?(MacroInt)
            MacroInt.new(left.value + right.value)
          elsif left.is_a?(MacroFloat) && right.is_a?(MacroFloat)
            MacroFloat.new(left.value + right.value)
          elsif left.is_a?(MacroInt) && right.is_a?(MacroFloat)
            MacroFloat.new(left.value.to_f64 + right.value)
          elsif left.is_a?(MacroFloat) && right.is_a?(MacroInt)
            MacroFloat.new(left.value + right.value.to_f64)
          else
            raise "Macro error: cannot add #{left.class} and #{right.class}"
          end
        when "-"
          if left.is_a?(MacroInt) && right.is_a?(MacroInt)
            MacroInt.new(left.value - right.value)
          elsif left.is_a?(MacroFloat) && right.is_a?(MacroFloat)
            MacroFloat.new(left.value - right.value)
          else
            raise "Macro error: cannot subtract #{left.class} and #{right.class}"
          end
        when "*"
          if left.is_a?(MacroInt) && right.is_a?(MacroInt)
            MacroInt.new(left.value * right.value)
          elsif left.is_a?(MacroFloat) && right.is_a?(MacroFloat)
            MacroFloat.new(left.value * right.value)
          else
            raise "Macro error: cannot multiply #{left.class} and #{right.class}"
          end
        when "/"
          if left.is_a?(MacroInt) && right.is_a?(MacroInt)
            MacroInt.new(left.value // right.value)
          elsif left.is_a?(MacroFloat) && right.is_a?(MacroFloat)
            MacroFloat.new(left.value / right.value)
          else
            raise "Macro error: cannot divide #{left.class} and #{right.class}"
          end
        when "%"
          if left.is_a?(MacroInt) && right.is_a?(MacroInt)
            MacroInt.new(left.value % right.value)
          else
            raise "Macro error: cannot mod #{left.class} and #{right.class}"
          end
        when "=="
          if left.is_a?(MacroInt) && right.is_a?(MacroInt)
            MacroBool.new(left.value == right.value)
          elsif left.is_a?(MacroString) && right.is_a?(MacroString)
            MacroBool.new(left.value == right.value)
          elsif left.is_a?(MacroBool) && right.is_a?(MacroBool)
            MacroBool.new(left.value == right.value)
          else
            MacroBool.new(false)
          end
        when "!="
          result = eval_binary("==", left, right)
          if result.is_a?(MacroBool)
            MacroBool.new(!result.value)
          else
            MacroBool.new(true)
          end
        when "<"
          if left.is_a?(MacroInt) && right.is_a?(MacroInt)
            MacroBool.new(left.value < right.value)
          else
            raise "Macro error: '<' requires Int operands"
          end
        when ">"
          if left.is_a?(MacroInt) && right.is_a?(MacroInt)
            MacroBool.new(left.value > right.value)
          else
            raise "Macro error: '>' requires Int operands"
          end
        when "<="
          if left.is_a?(MacroInt) && right.is_a?(MacroInt)
            MacroBool.new(left.value <= right.value)
          else
            raise "Macro error: '<=' requires Int operands"
          end
        when ">="
          if left.is_a?(MacroInt) && right.is_a?(MacroInt)
            MacroBool.new(left.value >= right.value)
          else
            raise "Macro error: '>=' requires Int operands"
          end
        when "&&"
          lb = truthy?(left)
          rb = truthy?(right)
          MacroBool.new(lb && rb)
        when "||"
          lb = truthy?(left)
          rb = truthy?(right)
          MacroBool.new(lb || rb)
        else
          raise "Macro error: unknown operator '#{op}'"
        end
      end

      private def eval_unary(op : String, operand : MacroValue) : MacroValue
        case op
        when "-"
          if operand.is_a?(MacroInt)
            MacroInt.new(-operand.value)
          elsif operand.is_a?(MacroFloat)
            MacroFloat.new(-operand.value)
          else
            raise "Macro error: cannot negate #{operand.class}"
          end
        when "!"
          MacroBool.new(!truthy?(operand))
        else
          raise "Macro error: unknown unary operator '#{op}'"
        end
      end


    end
  end
end
