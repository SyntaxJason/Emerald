require "../expressions"

module Emerald
  class Codegen
    private def emit_member_access(io : IO, expr : AST::MemberAccess)
      receiver = expr.receiver
      if receiver.is_a?(AST::ThisExpr)
        io << "@" << expr.name
      else
        emit_expr(io, receiver)
        io << "." << expr.name
      end
    end

    private def emit_method_call(io : IO, expr : AST::MethodCall)
      receiver_type = expr.receiver_type

      if expr.receiver.is_a?(AST::Identifier)
        recv_id = expr.receiver.as(AST::Identifier)
        if ["Fiber", "Thread", "VirtualThread", "Channel", "Mutex"].includes?(recv_id.name)
          return if emit_static_concurrency_call(io, expr, recv_id.name)
        end
      end

      if !receiver_type.empty? && emit_concurrency_instance_call(io, expr, receiver_type)
        return
      end

      if !receiver_type.empty? && (methods = BuiltinMethods.for_type(receiver_type))
        m = methods[expr.name]?
        if m
          recv_str = String.build do |sb|
            recv = expr.receiver
            if recv.is_a?(AST::ThisExpr)
              sb << "self"
            else
              emit_expr(sb, recv)
            end
          end
          arg_strs = expr.args.map do |arg|
            String.build { |sb| emit_expr(sb, arg) }
          end
          template = m.crystal_template
          template = template.gsub("%recv%", recv_str)
          arg_strs.each_with_index do |a, i|
            template = template.gsub("%a#{i}%", a)
          end
          io << template
          return
        end
      end

      receiver = expr.receiver
      if receiver.is_a?(AST::ThisExpr)
        io << expr.name
      else
        emit_expr(io, receiver)
        io << "." << expr.name
      end
      io << "("
      expr.args.each_with_index do |arg, i|
        io << ", " if i > 0
        emit_expr(io, arg)
      end
      io << ")"
    end

    private def emit_member_assign(io : IO, expr : AST::MemberAssign)
      receiver = expr.receiver
      if receiver.is_a?(AST::ThisExpr)
        io << "@" << expr.name
      else
        emit_expr(io, receiver)
        io << "." << expr.name
      end
      io << " = "
      emit_expr(io, expr.value)
    end

  end
end
