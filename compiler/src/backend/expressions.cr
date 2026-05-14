module Emerald
  class Codegen
    def emit_expr(io : IO, expr : AST::Node)
      case expr
      when AST::IntLiteral    then io << expr.value.to_s << "_i64"
      when AST::FloatLiteral  then io << expr.value.to_s
      when AST::StringLiteral then io << expr.value.inspect
      when AST::CharLiteral
        io << "'" << escape_char(expr.value) << "'"
      when AST::BoolLiteral   then io << (expr.value ? "true" : "false")
      when AST::Identifier    then io << expr.name
      when AST::ThisExpr      then io << "self"
      when AST::BinaryOp      then emit_binary(io, expr)
      when AST::UnaryOp       then io << expr.op; emit_expr(io, expr.operand)
      when AST::QuoteExpr     then raise "quote expressions are compile-time only"
      when AST::UnquoteExpr   then raise "unquote expressions are compile-time only"
      when AST::CallExpr      then emit_call(io, expr)
      when AST::NewExpr       then emit_new(io, expr)
      when AST::MemberAccess  then emit_member_access(io, expr)
      when AST::MethodCall    then emit_method_call(io, expr)
      when AST::MemberAssign  then emit_member_assign(io, expr)
      when AST::RangeExpr
        emit_expr(io, expr.start)
        io << (expr.inclusive ? ".." : "...")
        emit_expr(io, expr.finish)
      when AST::StringInterp  then emit_interp(io, expr)
      when AST::OkExpr
        io << "EmeraldResult.ok("
        emit_expr(io, expr.value)
        io << ")"
      when AST::ErrExpr
        io << "EmeraldResult.err("
        emit_expr(io, expr.value)
        io << ")"
      when AST::LambdaExpr   then emit_lambda(io, expr)
      when AST::MethodRef    then emit_method_ref(io, expr)
      when AST::MatchExpr    then emit_match(io, expr)
      else
        raise "Unknown expression: #{expr.class}"
      end
    end

    private def emit_binary(io : IO, expr : AST::BinaryOp)
      crystal_op = if expr.op == "/" && expr.result_type == "Int"
                     "//"
                   else
                     expr.op
                   end
      io << "("
      emit_expr(io, expr.left)
      io << " " << crystal_op << " "
      emit_expr(io, expr.right)
      io << ")"
    end

  end
end

require "./expressions/calls"
require "./expressions/members"
require "./expressions/lambdas"
