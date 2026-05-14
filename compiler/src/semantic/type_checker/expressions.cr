require "../type_checker"

module Emerald
  class TypeChecker
    def check_expr(expr : AST::Node, scope : Scope) : String
      case expr
      when AST::IntLiteral    then "Int"
      when AST::FloatLiteral  then "Float"
      when AST::StringLiteral then "String"
      when AST::StringInterp  then check_string_interp(expr, scope); "String"
      when AST::CharLiteral   then "Char"
      when AST::BoolLiteral   then "Bool"
      when AST::Identifier
        sym = scope.lookup(expr.name)
        raise TypeError.new("Undefined identifier '#{expr.name}'", expr.line, expr.col) unless sym
        case sym
        when VarSymbol then sym.as(VarSymbol).type_name
        when TypeSymbol then sym.as(TypeSymbol).fqn
        else
          raise TypeError.new("'#{expr.name}' is not a value", expr.line, expr.col)
        end
      when AST::ThisExpr
        sym = scope.lookup("this").as(VarSymbol)
        sym.type_name
      when AST::BinaryOp
        check_binary(expr, scope)
      when AST::UnaryOp
        check_unary(expr, scope)
      when AST::QuoteExpr
        quote_expr_type(expr)
      when AST::UnquoteExpr
        raise TypeError.new("Unquote can only be used inside quote blocks", expr.line, expr.col, "Use $(...) only inside quote expr, quote stmt or quote block", 2)
      when AST::CallExpr
        check_call(expr, scope)
      when AST::NewExpr
        check_new(expr, scope)
      when AST::MemberAccess
        check_member_access(expr, scope)
      when AST::MethodCall
        check_method_call(expr, scope)
      when AST::MemberAssign
        check_member_assign(expr, scope)
      when AST::RangeExpr
        s = check_expr(expr.start, scope)
        e = check_expr(expr.finish, scope)
        unless s == "Int" && e == "Int"
          raise TypeError.new("Range bounds must be Int, got #{s}..#{e}", expr.line, expr.col)
        end
        "Range"
      when AST::OkExpr
        inner = check_expr(expr.value, scope)
        "Result<#{inner},?>"
      when AST::ErrExpr
        inner = check_expr(expr.value, scope)
        "Result<?,#{inner}>"
      when AST::LambdaExpr
        check_lambda(expr, scope)
      when AST::MethodRef
        check_method_ref(expr, scope)
      when AST::MatchExpr
        check_match(expr, scope)
      when AST::ListLiteral
        expr.elements.each { |e| check_expr(e, scope) }
        "List<ExpressionAST>"
      when AST::IndexExpr
        check_expr(expr.receiver, scope)
        check_expr(expr.index, scope)
        "Any"
      else
        raise TypeError.new("Cannot type-check expression: #{expr.class}", expr.line, expr.col)
      end
    end

    private def quote_expr_type(expr : AST::QuoteExpr) : String
      case expr.kind
      when "expr"   then "ExpressionAST"
      when "stmt"   then "StatementAST"
      when "block"  then "BlockAST"
      when "method" then "MethodAST"
      when "field"  then "FieldAST"
      else
        raise TypeError.new("Unknown quote kind '#{expr.kind}'", expr.line, expr.col)
      end
    end

    private def check_string_interp(expr : AST::StringInterp, scope : Scope)
      expr.parts.each do |part|
        if part.is_a?(AST::InterpExpr)
          check_expr(part.as(AST::InterpExpr).expression, scope)
        end
      end
    end

    private def check_binary(expr : AST::BinaryOp, scope : Scope) : String
      lt = check_expr(expr.left, scope)
      rt = check_expr(expr.right, scope)
      result = case expr.op
               when "+", "-", "*", "/", "%"
                 if expr.op == "+" && lt == "String" && rt == "String"
                   "String"
                 elsif !(TypeSystem.numeric?(lt) && TypeSystem.numeric?(rt))
                   raise TypeError.new("Operator '#{expr.op}' requires numeric operands, got #{lt} and #{rt}", expr.line, expr.col)
                 else
                   TypeSystem.promote_numeric(lt, rt)
                 end
               when "==", "!="
                 unless types_compatible?(lt, rt) || types_compatible?(rt, lt)
                   raise TypeError.new("Cannot compare #{lt} with #{rt}", expr.line, expr.col)
                 end
                 "Bool"
               when "<", ">", "<=", ">="
                 unless TypeSystem.numeric?(lt) && TypeSystem.numeric?(rt)
                   raise TypeError.new("Comparison '#{expr.op}' requires numeric operands, got #{lt} and #{rt}", expr.line, expr.col)
                 end
                 "Bool"
               when "&&", "||"
                 unless lt == "Bool" && rt == "Bool"
                   raise TypeError.new("Logical '#{expr.op}' requires Bool operands, got #{lt} and #{rt}", expr.line, expr.col)
                 end
                 "Bool"
               when ".."
                 unless lt == "Int" && rt == "Int"
                   raise TypeError.new("Range bounds must be Int, got #{lt}..#{rt}", expr.line, expr.col)
                 end
                 "Range"
               else
                 raise TypeError.new("Unknown binary operator '#{expr.op}'", expr.line, expr.col)
               end
      expr.result_type = result
      result
    end

    private def check_unary(expr : AST::UnaryOp, scope : Scope) : String
      t = check_expr(expr.operand, scope)
      case expr.op
      when "-", "+"
        unless TypeSystem.numeric?(t)
          raise TypeError.new("Unary '#{expr.op}' requires numeric operand, got #{t}", expr.line, expr.col)
        end
        t
      when "!"
        unless t == "Bool"
          raise TypeError.new("Unary '!' requires Bool, got #{t}", expr.line, expr.col)
        end
        "Bool"
      else
        raise TypeError.new("Unknown unary operator '#{expr.op}'", expr.line, expr.col)
      end
    end

  end
end
