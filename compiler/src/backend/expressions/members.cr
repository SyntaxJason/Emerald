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

        return if emit_static_stdlib_call(io, expr, recv_id.name)

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

    private def emit_static_stdlib_call(io : IO, expr : AST::MethodCall, type_name : String) : Bool
      case {type_name, expr.name}
      when {"Duration", "millis"}
        emit_duration_factory(io, expr, "1_i64")
        return true
      when {"Duration", "seconds"}
        emit_duration_factory(io, expr, "1000_i64")
        return true
      when {"Duration", "minutes"}
        emit_duration_factory(io, expr, "60000_i64")
        return true
      when {"Duration", "hours"}
        emit_duration_factory(io, expr, "3600000_i64")
        return true
      when {"Duration", "days"}
        emit_duration_factory(io, expr, "86400000_i64")
        return true
      when {"OffsetDateTime", "now"}
        emit_offset_date_time_now(io, false)
        return true
      when {"OffsetDateTime", "utcNow"}
        emit_offset_date_time_now(io, true)
        return true
      when {"OffsetDateTime", "of"}
        emit_offset_date_time_of(io, expr)
        return true
      when {"Console", "print"}
        emit_static_console_call(io, expr, "print")
        return true
      when {"Console", "println"}
        emit_static_console_call(io, expr, "puts")
        return true
      when {"Console", "error"}
        emit_static_console_call(io, expr, "STDERR.puts")
        return true
      when {"Math", "abs"}
        emit_static_math_abs(io, expr)
        return true
      when {"Math", "min"}
        emit_static_math_pair(io, expr, "min")
        return true
      when {"Math", "max"}
        emit_static_math_pair(io, expr, "max")
        return true
      when {"Math", "clamp"}
        emit_static_math_clamp(io, expr)
        return true
      end

      false
    end

    private def emit_duration_factory(io : IO, expr : AST::MethodCall, factor : String)
      io << crystal_type("Duration") << ".new(("
      emit_expr(io, expr.args[0])
      io << ") * " << factor << ")"
    end

    private def emit_offset_date_time_now(io : IO, utc : Bool)
      time_call = utc ? "Time.utc" : "Time.local"

      io << "begin\n"
      io << "__emerald_now = " << time_call << "\n"
      unless utc
        io << "__emerald_offset_raw = __emerald_now.to_s(\"%z\")\n"
        io << "__emerald_offset_sign = __emerald_offset_raw[0] == '-' ? -1_i64 : 1_i64\n"
        io << "__emerald_offset_hours = __emerald_offset_raw[1, 2].to_i64\n"
        io << "__emerald_offset_minutes_part = __emerald_offset_raw[3, 2].to_i64\n"
        io << "__emerald_offset_minutes = __emerald_offset_sign * ((__emerald_offset_hours * 60_i64) + __emerald_offset_minutes_part)\n"
      end
      io << crystal_type("OffsetDateTime") << ".new("
      io << "__emerald_now.year.to_i64, "
      io << "__emerald_now.month.to_i64, "
      io << "__emerald_now.day.to_i64, "
      io << "__emerald_now.hour.to_i64, "
      io << "__emerald_now.minute.to_i64, "
      io << "__emerald_now.second.to_i64, "
      io << (utc ? "0_i64" : "__emerald_offset_minutes")
      io << ")\n"
      io << "end"
    end

    private def emit_offset_date_time_of(io : IO, expr : AST::MethodCall)
      io << crystal_type("OffsetDateTime") << ".new("
      expr.args.each_with_index do |arg, index|
        io << ", " if index > 0
        emit_expr(io, arg)
      end
      io << ")"
    end

    private def emit_static_console_call(io : IO, expr : AST::MethodCall, target : String)
      io << target << "("
      emit_expr(io, expr.args[0])
      io << ")"
    end

    private def emit_static_math_abs(io : IO, expr : AST::MethodCall)
      io << "("
      emit_expr(io, expr.args[0])
      io << ").abs"
    end

    private def emit_static_math_pair(io : IO, expr : AST::MethodCall, operation : String)
      io << "(["
      emit_expr(io, expr.args[0])
      io << ", "
      emit_expr(io, expr.args[1])
      io << "]." << operation << ")"
    end

    private def emit_static_math_clamp(io : IO, expr : AST::MethodCall)
      io << "([(["
      emit_expr(io, expr.args[0])
      io << ", "
      emit_expr(io, expr.args[1])
      io << "].max), "
      emit_expr(io, expr.args[2])
      io << "].min)"
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
