require "../interpreter"

module Emerald
  module MacroEngine
    class Interpreter
      private def expression_to_string(node : AST::Node) : String
        case node
        when AST::StringLiteral
          node.value
        when AST::IntLiteral
          node.value.to_s
        when AST::FloatLiteral
          node.value.to_s
        when AST::BoolLiteral
          node.value.to_s
        when AST::Identifier
          node.name
        else
          node.to_s
        end
      end

      private def expression_to_int(node : AST::Node) : Int64
        case node
        when AST::IntLiteral
          node.value
        when AST::StringLiteral
          node.value.to_i64
        else
          raise "Macro error: cannot convert #{node.class} to Int"
        end
      end

      private def expression_to_float(node : AST::Node) : Float64
        case node
        when AST::FloatLiteral
          node.value
        when AST::IntLiteral
          node.value.to_f64
        when AST::StringLiteral
          node.value.to_f64
        else
          raise "Macro error: cannot convert #{node.class} to Float"
        end
      end

      private def expression_to_bool(node : AST::Node) : Bool
        case node
        when AST::BoolLiteral
          node.value
        when AST::StringLiteral
          node.value == "true"
        else
          raise "Macro error: cannot convert #{node.class} to Bool"
        end
      end

      private def truthy?(val : MacroValue) : Bool
        case val
        when MacroBool   then val.value
        when MacroInt    then val.value != 0
        when MacroFloat  then val.value != 0.0
        when MacroString then !val.value.empty?
        when MacroList   then !val.value.empty?
        when MacroVoid   then false
        when MacroASTRef then true
        else
          true
        end
      end

      private def value_to_string(val : MacroValue) : String
        case val
        when MacroInt    then val.value.to_s
        when MacroFloat  then val.value.to_s
        when MacroString then val.value
        when MacroBool   then val.value.to_s
        when MacroVoid   then ""
        when MacroList   then "[#{val.value.map { |v| value_to_string(v) }.join(", ")}]"
        when MacroASTRef then "<#{val.type_name}>"
        else
          "<unknown>"
        end
      end
    end
  end
end
