require "./interpreter/values"
require "../frontend/ast"

module Emerald
  module MacroEngine
    class Interpreter
      @scope : MacroScope

      def initialize
        @scope = MacroScope.new
      end

      def run(body : AST::Block, target_node : AST::Node, target_type : String, args : Array(AST::Node)) : AST::Node?
        @scope = MacroScope.new
        ast_type = target_type == "Method" ? "MethodAST" : "ClassAST"
        @scope.declare(target_type.downcase, MacroASTRef.new(target_node, ast_type))

        arg_list = [] of MacroValue
        args.each { |a| arg_list << MacroASTRef.new(a, "ExpressionAST") }
        @scope.declare("args", MacroList.from(arg_list))

        eval_block(body)
        nil
      end

      def eval_stmt(stmt : AST::Node) : MacroValue
        case stmt
        when AST::VarDecl
          init_val = stmt.initializer ? eval_expr(stmt.initializer.not_nil!) : MacroVoid.new
          @scope.declare(stmt.name, init_val)
          init_val
        when AST::AssignStmt
          val = eval_expr(stmt.value)
          @scope.set(stmt.target, val)
          val
        when AST::ExpressionStmt
          eval_expr(stmt.expression)
        when AST::ReturnStmt
          if v = stmt.value
            val = eval_expr(v)
            raise MacroReturn.new(val)
          else
            raise MacroReturn.new(MacroVoid.new)
          end
        when AST::IfStmt
          cond = eval_expr(stmt.condition)
          if truthy?(cond)
            eval_block(stmt.then_branch)
          elsif eb = stmt.else_branch
            case eb
            when AST::Block then eval_block(eb)
            when AST::IfStmt then eval_stmt(eb)
            else MacroVoid.new
            end
          else
            MacroVoid.new
          end
        when AST::WhileStmt
          while truthy?(eval_expr(stmt.condition))
            eval_block(stmt.body)
          end
          MacroVoid.new
        when AST::ForStmt
          iter = eval_expr(stmt.iterable)
          if iter.is_a?(MacroASTRef) && iter.type_name == "Range"
            range_node = iter.node
            if range_node.is_a?(AST::RangeExpr)
              start_val = eval_expr(range_node.start)
              end_val = eval_expr(range_node.finish)
              if start_val.is_a?(MacroInt) && end_val.is_a?(MacroInt)
                s = start_val.value
                e = end_val.value
                step = range_node.inclusive ? 1i64 : 1i64
                limit = range_node.inclusive ? e : e - 1
                (s..limit).each do |i|
                  body_scope = MacroScope.new(@scope)
                  old_scope = @scope
                  @scope = body_scope
                  @scope.declare(stmt.var_name, MacroInt.new(i))
                  eval_block(stmt.body)
                  @scope = old_scope
                end
              end
            end
          end
          MacroVoid.new
        when AST::Block
          eval_block(stmt)
        else
          MacroVoid.new
        end
      rescue ex : MacroReturn
        ex.value
      end

      def eval_block(block : AST::Block) : MacroValue
        last = MacroVoid.new
        block.statements.each do |s|
          last = eval_stmt(s)
        end
        last
      end

      def eval_expr(expr : AST::Node) : MacroValue
        case expr
        when AST::IntLiteral
          MacroInt.new(expr.value)
        when AST::FloatLiteral
          MacroFloat.new(expr.value)
        when AST::StringLiteral
          MacroString.new(expr.value)
        when AST::BoolLiteral
          MacroBool.new(expr.value)
        when AST::StringInterp
          result = ""
          expr.parts.each do |part|
            case part
            when AST::InterpText
              result += part.value
            when AST::InterpExpr
              val = eval_expr(part.expression)
              result += value_to_string(val)
            end
          end
          MacroString.new(result)
        when AST::Identifier
          sym = @scope.lookup(expr.name)
          raise "Macro error: undefined variable '#{expr.name}' at #{expr.line}:#{expr.col}" unless sym
          sym
        when AST::BinaryOp
          left = eval_expr(expr.left)
          right = eval_expr(expr.right)
          eval_binary(expr.op, left, right)
        when AST::UnaryOp
          operand = eval_expr(expr.operand)
          eval_unary(expr.op, operand)
        when AST::RangeExpr
          MacroASTRef.new(expr, "Range")
        when AST::QuoteExpr
          eval_quote_expr(expr)
        when AST::UnquoteExpr
          raise "Macro error: unquote can only be used inside quote blocks"
        when AST::CallExpr
          eval_call(expr)
        when AST::MethodCall
          eval_method_call(expr)
        when AST::MemberAccess
          eval_member_access(expr)
        when AST::MemberAssign
          eval_member_assign(expr)
        when AST::ThisExpr
          sym = @scope.lookup("method") || @scope.lookup("class")
          raise "Macro error: 'this' used outside of macro body" unless sym
          sym
        when AST::ListLiteral
          items = [] of MacroValue
          expr.elements.each { |e| items << eval_expr(e) }
          MacroList.from(items)
        when AST::IndexExpr
          receiver = eval_expr(expr.receiver)
          index = eval_expr(expr.index)
          if receiver.is_a?(MacroList) && index.is_a?(MacroInt)
            idx = index.value
            if idx >= 0 && idx < receiver.value.size
              receiver.value[idx]
            else
              raise "Macro error: index #{idx} out of bounds for list of size #{receiver.value.size}"
            end
          else
            raise "Macro error: index access requires a list and an integer index"
          end
        else
          raise "Macro error: unsupported expression '#{expr.class}' at #{expr.line}:#{expr.col}"
        end
      end
    end
  end
end

require "./interpreter/quotes"
require "./interpreter/operators"
require "./interpreter/calls"
require "./interpreter/ast_access"
require "./interpreter/builders"
require "./interpreter/expectations"
require "./interpreter/conversions"

