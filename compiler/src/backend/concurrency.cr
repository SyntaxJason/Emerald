require "./base"

module Emerald
  class Codegen
    def emit_static_concurrency_call(io : IO, expr : AST::MethodCall, type_name : String) : Bool
      case {type_name, expr.name}
      when {"Fiber", "spawn"}
        emit_fiber_spawn(io, expr)
        return true
      when {"Thread", "spawn"}
        emit_thread_spawn(io, expr)
        return true
      when {"VirtualThread", "spawn"}
        emit_fiber_spawn(io, expr)
        return true
      when {"Mutex", "new"}
        io << "Mutex.new"
        return true
      when {"Channel", "new"}
        ch_type = if expr.receiver_type.starts_with?("Channel<")
                    inner = expr.receiver_type[(expr.receiver_type.index("<").not_nil! + 1)..-2]
                    crystal_type(inner)
                  else
                    "Object"
                  end
        io << "Channel(" << ch_type << ").new"
        return true
      end
      false
    end

    private def emit_fiber_spawn(io : IO, expr : AST::MethodCall)
      lambda = expr.args[0]
      io << "EmeraldFiber.spawn { "
      if lambda.is_a?(AST::LambdaExpr)
        body = lambda.as(AST::LambdaExpr).body
        if body.is_a?(AST::Block)
          io << "begin\n"
          @indent += 1
          body.as(AST::Block).statements.each { |s| emit_stmt(io, s) }
          @indent -= 1
          indent(io); io << "end "
        else
          emit_expr(io, body)
          io << " "
        end
      else
        emit_expr(io, lambda)
        io << ".call"
      end
      io << "}"
    end

    private def emit_thread_spawn(io : IO, expr : AST::MethodCall)
      lambda = expr.args[0]
      io << "EmeraldThread.spawn { "
      if lambda.is_a?(AST::LambdaExpr)
        body = lambda.as(AST::LambdaExpr).body
        if body.is_a?(AST::Block)
          io << "begin\n"
          @indent += 1
          body.as(AST::Block).statements.each { |s| emit_stmt(io, s) }
          @indent -= 1
          indent(io); io << "end "
        else
          emit_expr(io, body)
          io << " "
        end
      else
        emit_expr(io, lambda)
        io << ".call"
      end
      io << "}"
    end

    def emit_concurrency_instance_call(io : IO, expr : AST::MethodCall, receiver_type : String) : Bool
      if receiver_type.starts_with?("Fiber<") ||
         receiver_type.starts_with?("Thread<") ||
         receiver_type.starts_with?("VirtualThread<")
        case expr.name
        when "await"
          emit_expr(io, expr.receiver)
          io << ".await"
          return true
        end
      elsif receiver_type == "Mutex"
        case expr.name
        when "lock"
          emit_expr(io, expr.receiver)
          io << ".lock"
          return true
        when "unlock"
          emit_expr(io, expr.receiver)
          io << ".unlock"
          return true
        when "synchronize"
          emit_expr(io, expr.receiver)
          io << ".synchronize { "
          lambda = expr.args[0]
          if lambda.is_a?(AST::LambdaExpr)
            body = lambda.as(AST::LambdaExpr).body
            if body.is_a?(AST::Block)
              body.as(AST::Block).statements.each { |s| emit_stmt(io, s) }
            else
              emit_expr(io, body)
            end
          else
            emit_expr(io, lambda)
            io << ".call"
          end
          io << " }"
          return true
        end
      elsif receiver_type.starts_with?("Channel<")
        case expr.name
        when "send"
          emit_expr(io, expr.receiver)
          io << ".send("
          emit_expr(io, expr.args[0])
          io << ")"
          return true
        when "receive"
          emit_expr(io, expr.receiver)
          io << ".receive"
          return true
        when "close"
          emit_expr(io, expr.receiver)
          io << ".close"
          return true
        end
      end
      false
    end
  end
end
