require "../interpreter"

module Emerald
  module MacroEngine
    class Interpreter
      private def eval_member_access(expr : AST::MemberAccess) : MacroValue
        receiver = eval_expr(expr.receiver)
        if receiver.is_a?(MacroASTRef)
          return eval_ast_property(receiver, expr.name)
        end
        raise "Macro error: cannot access member '#{expr.name}' on #{receiver.class}"
      end

      private def eval_member_assign(expr : AST::MemberAssign) : MacroValue
        receiver = eval_expr(expr.receiver)
        value = eval_expr(expr.value)
        if receiver.is_a?(MacroASTRef)
          return eval_ast_set_property(receiver, expr.name, value)
        end
        raise "Macro error: cannot assign member '#{expr.name}' on #{receiver.class}"
      end


      private def eval_ast_property(ref : MacroASTRef, prop : String) : MacroValue
        node = ref.node
        case ref.type_name
        when "MethodAST"
          method_node = node.as(AST::MethodDecl)
          case prop
          when "name"       then MacroString.new(method_node.name)
          when "returnType" then MacroString.new(method_node.return_type.to_s)
          when "body"       then MacroASTRef.new(method_node.body.not_nil!, "BlockAST")
          when "isStatic"   then MacroBool.new(false)
          when "visibility" then MacroString.new(method_node.visibility.to_s)
          when "params"
            list = [] of MacroValue
            method_node.params.each { |p| list << MacroASTRef.new(p, "ParamAST") }
            MacroList.from(list)
          else
            raise "Macro error: MethodAST has no property '#{prop}'"
          end
        when "ClassAST"
          class_node = node.as(AST::ClassDecl)
          case prop
          when "name"    then MacroString.new(class_node.name)
          when "methods"
            list = [] of MacroValue
            class_node.methods.each { |m| list << MacroASTRef.new(m, "MethodAST") }
            MacroList.from(list)
          when "fields"
            list = [] of MacroValue
            class_node.fields.each { |f| list << MacroASTRef.new(f, "FieldAST") }
            MacroList.from(list)
          else
            raise "Macro error: ClassAST has no property '#{prop}'"
          end
        when "BlockAST"
          block_node = node.as(AST::Block)
          case prop
          when "length" then MacroInt.new(block_node.statements.size.to_i64)
          else
            raise "Macro error: BlockAST has no property '#{prop}'"
          end
        when "ParamAST"
          param_node = node.as(AST::Param)
          case prop
          when "name" then MacroString.new(param_node.name)
          when "type" then MacroString.new(param_node.type_ref.to_s)
          else
            raise "Macro error: ParamAST has no property '#{prop}'"
          end
        when "FieldAST"
          field_node = node.as(AST::FieldDecl)
          case prop
          when "name"       then MacroString.new(field_node.name)
          when "type"       then MacroString.new(field_node.type_ref.to_s)
          when "visibility" then MacroString.new(field_node.visibility.to_s)
          else
            raise "Macro error: FieldAST has no property '#{prop}'"
          end
        when "ExpressionAST"
          raise "Macro error: cannot access property '#{prop}' on ExpressionAST"
        else
          raise "Macro error: unknown AST type '#{ref.type_name}'"
        end
      end

      private def eval_ast_set_property(ref : MacroASTRef, prop : String, value : MacroValue) : MacroValue
        case ref.type_name
        when "BlockAST"
          block_node = ref.node.as(AST::Block)
          raise "Macro error: cannot set property '#{prop}' on BlockAST directly"
        else
          raise "Macro error: cannot set property '#{prop}' on #{ref.type_name}"
        end
      end


      private def eval_ast_method(ref : MacroASTRef, method : String, args : Array(MacroValue)) : MacroValue
        case ref.type_name
        when "BlockAST"
          block_node = ref.node.as(AST::Block)
          case method
          when "prepend"
            block_node.statements.insert(0, expect_statement_value(args, 0))
            return MacroVoid.new
          when "append"
            block_node.statements << expect_statement_value(args, 0)
            return MacroVoid.new
          when "insertAt"
            idx = expect_int_arg(args, 0)
            block_node.statements.insert(idx.to_i, expect_statement_value(args, 1))
            return MacroVoid.new
          when "replace"
            idx = expect_int_arg(args, 0)
            block_node.statements[idx] = expect_statement_value(args, 1) if idx < block_node.statements.size
            return MacroVoid.new
          when "get"
            idx = expect_int_arg(args, 0)
            return MacroASTRef.new(block_node.statements[idx], "StatementAST") if idx < block_node.statements.size
          end
        when "ClassAST"
          class_node = ref.node.as(AST::ClassDecl)
          case method
          when "addMethod"
            method_node = expect_ast_value(args, 0, "MethodAST")
            class_node.methods << method_node.as(AST::MethodDecl)
            return MacroVoid.new
          when "addField"
            field_node = expect_ast_value(args, 0, "FieldAST")
            class_node.fields << field_node.as(AST::FieldDecl)
            return MacroVoid.new
          end
        when "ExpressionAST"
          case method
          when "toString"
            return MacroString.new(expression_to_string(ref.node))
          when "toInt"
            return MacroInt.new(expression_to_int(ref.node))
          when "toFloat"
            return MacroFloat.new(expression_to_float(ref.node))
          when "toBool"
            return MacroBool.new(expression_to_bool(ref.node))
          end
        when "MethodAST"
          case method
          when "create"
          end
        end

        raise "Macro error: unknown method '#{method}' on #{ref.type_name}"
      end


    end
  end
end
