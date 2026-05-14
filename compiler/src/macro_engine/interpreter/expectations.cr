require "../interpreter"

module Emerald
  module MacroEngine
    class Interpreter
      private def wrap_ast(node : AST::Node, type : String) : MacroValue
        MacroASTRef.new(node, type)
      end

      private def expect_arg(args : Array(MacroValue), idx : Int) : MacroValue
        arg = args[idx]?
        raise "Macro error: missing argument at index #{idx}" unless arg
        arg
      end

      private def expect_ast_value(args : Array(MacroValue), idx : Int, type_name : String) : AST::Node
        arg = expect_arg(args, idx)
        if arg.is_a?(MacroASTRef)
          raise "Macro error: expected #{type_name} at index #{idx}, got #{arg.type_name}" unless arg.type_name == type_name
          return arg.node
        end
        raise "Macro error: expected #{type_name} at index #{idx}, got #{arg.class}"
      end

      private def expect_expression_arg(args : Array(MacroValue), idx : Int) : AST::Node
        expect_ast_value(args, idx, "ExpressionAST")
      end

      private def expect_statement_value(args : Array(MacroValue), idx : Int) : AST::Node
        expect_ast_value(args, idx, "StatementAST")
      end

      private def expect_block_arg(args : Array(MacroValue), idx : Int) : AST::Block
        expect_ast_value(args, idx, "BlockAST").as(AST::Block)
      end

      private def expect_string_arg(args : Array(MacroValue), idx : Int) : String
        arg = expect_arg(args, idx)
        case arg
        when MacroString
          arg.value
        when MacroInt
          arg.value.to_s
        when MacroFloat
          arg.value.to_s
        when MacroBool
          arg.value.to_s
        when MacroASTRef
          expression_to_string(arg.node)
        else
          raise "Macro error: expected String at index #{idx}, got #{arg.class}"
        end
      end

      private def expect_int_arg(args : Array(MacroValue), idx : Int) : Int64
        arg = expect_arg(args, idx)
        case arg
        when MacroInt
          arg.value
        when MacroString
          arg.value.to_i64
        when MacroASTRef
          expression_to_int(arg.node)
        else
          raise "Macro error: expected Int at index #{idx}, got #{arg.class}"
        end
      end

      private def expect_float_arg(args : Array(MacroValue), idx : Int) : Float64
        arg = expect_arg(args, idx)
        case arg
        when MacroFloat
          arg.value
        when MacroInt
          arg.value.to_f64
        when MacroString
          arg.value.to_f64
        when MacroASTRef
          expression_to_float(arg.node)
        else
          raise "Macro error: expected Float at index #{idx}, got #{arg.class}"
        end
      end

      private def expect_bool_arg(args : Array(MacroValue), idx : Int) : Bool
        arg = expect_arg(args, idx)
        case arg
        when MacroBool
          arg.value
        when MacroString
          arg.value == "true"
        when MacroASTRef
          expression_to_bool(arg.node)
        else
          raise "Macro error: expected Bool at index #{idx}, got #{arg.class}"
        end
      end

      private def expect_expr_list_arg(args : Array(MacroValue), idx : Int) : Array(AST::Node)
        arg = expect_arg(args, idx)
        raise "Macro error: expected List<ExpressionAST> at index #{idx}, got #{arg.class}" unless arg.is_a?(MacroList)

        result = [] of AST::Node
        arg.value.each_with_index do |item, item_idx|
          if item.is_a?(MacroASTRef) && item.type_name == "ExpressionAST"
            result << item.node
            next
          end
          raise "Macro error: expected ExpressionAST in list at index #{item_idx}, got #{item.class}"
        end
        result
      end

      private def expect_stmt_list_arg(args : Array(MacroValue), idx : Int) : Array(AST::Node)
        arg = expect_arg(args, idx)
        raise "Macro error: expected List<StatementAST> at index #{idx}, got #{arg.class}" unless arg.is_a?(MacroList)

        result = [] of AST::Node
        arg.value.each_with_index do |item, item_idx|
          if item.is_a?(MacroASTRef) && item.type_name == "StatementAST"
            result << item.node
            next
          end
          raise "Macro error: expected StatementAST in list at index #{item_idx}, got #{item.class}"
        end
        result
      end

      private def expect_param_list_arg(args : Array(MacroValue), idx : Int) : Array(AST::Param)
        arg = expect_arg(args, idx)
        raise "Macro error: expected List<ParamAST> at index #{idx}, got #{arg.class}" unless arg.is_a?(MacroList)

        result = [] of AST::Param
        arg.value.each_with_index do |item, item_idx|
          if item.is_a?(MacroASTRef) && item.type_name == "ParamAST"
            result << item.node.as(AST::Param)
            next
          end
          raise "Macro error: expected ParamAST in list at index #{item_idx}, got #{item.class}"
        end
        result
      end

    end
  end
end
