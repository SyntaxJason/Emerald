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
      intrinsic = RuntimeStaticIntrinsics.find(type_name, expr.name)
      return false unless intrinsic

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
      when {"Console", "write"}
        emit_static_console_call(io, expr, "print")
        return true
      when {"Console", "writeLine"}
        emit_static_console_call(io, expr, "puts")
        return true
      when {"Console", "errorLine"}
        emit_static_console_call(io, expr, "STDERR.puts")
        return true
      when {"Console", "blankLine"}
        emit_static_console_blank_line(io)
        return true
      when {"Console", "readLine"}
        emit_static_console_read_line(io)
        return true
      when {"Console", "readLineOr"}
        emit_static_console_read_line_or(io, expr)
        return true
      when {"Console", "tryReadLine"}
        emit_static_console_try_read_line(io)
        return true
      when {"Console", "prompt"}
        emit_static_console_prompt(io, expr)
        return true
      when {"Console", "promptOr"}
        emit_static_console_prompt_or(io, expr)
        return true
      when {"Console", "confirm"}
        emit_static_console_confirm(io, expr)
        return true
      when {"Console", "confirmOr"}
        emit_static_console_confirm_or(io, expr)
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
      when {"Path", "current"}
        emit_static_path_current(io)
        return true
      when {"Path", "join"}
        emit_static_path_join(io, expr)
        return true
      when {"Path", "fileName"}
        emit_static_path_single(io, expr, "basename")
        return true
      when {"Path", "extension"}
        emit_static_path_single(io, expr, "extname")
        return true
      when {"Path", "parent"}
        emit_static_path_single(io, expr, "dirname")
        return true
      when {"File", "readText"}
        emit_static_file_read_text(io, expr)
        return true
      when {"File", "readLines"}
        emit_static_file_read_lines(io, expr)
        return true
      when {"File", "writeText"}
        emit_static_file_write_text(io, expr)
        return true
      when {"File", "appendText"}
        emit_static_file_append_text(io, expr)
        return true
      when {"File", "tryReadText"}
        emit_static_file_try_read_text(io, expr)
        return true
      when {"File", "tryWriteText"}
        emit_static_file_try_write_text(io, expr)
        return true
      when {"File", "tryAppendText"}
        emit_static_file_try_append_text(io, expr)
        return true
      when {"File", "exists"}
        emit_static_file_predicate(io, expr, "exists?")
        return true
      when {"File", "isFile"}
        emit_static_file_predicate(io, expr, "file?")
        return true
      when {"File", "isDirectory"}
        emit_static_file_directory_predicate(io, expr)
        return true
      when {"File", "delete"}
        emit_static_file_delete(io, expr)
        return true
      when {"File", "size"}
        emit_static_file_size(io, expr)
        return true
      when {"Directory", "exists"}
        emit_static_directory_predicate(io, expr)
        return true
      when {"Directory", "create"}
        emit_static_directory_create(io, expr)
        return true
      when {"Directory", "delete"}
        emit_static_directory_delete(io, expr)
        return true
      when {"Directory", "list"}
        emit_static_directory_list(io, expr)
        return true
      when {"Http", "get"}
        emit_static_http_get(io, expr)
        return true
      when {"Http", "postText"}
        emit_static_http_post_text(io, expr)
        return true
      when {"Tcp", "connect"}
        emit_static_tcp_connect(io, expr)
        return true
      when {"Tcp", "listen"}
        emit_static_tcp_listen(io, expr)
        return true
      when {"Tcp", "isOpen"}
        emit_static_tcp_handle_predicate(io, expr, "socket_open?")
        return true
      when {"Tcp", "listenerIsOpen"}
        emit_static_tcp_handle_predicate(io, expr, "listener_open?")
        return true
      when {"Tcp", "readText"}
        emit_static_tcp_handle_string(io, expr, "read_text")
        return true
      when {"Tcp", "readLine"}
        emit_static_tcp_handle_string(io, expr, "read_line")
        return true
      when {"Tcp", "tryReadText"}
        emit_static_tcp_try_read(io, expr, "read_text")
        return true
      when {"Tcp", "tryReadLine"}
        emit_static_tcp_try_read(io, expr, "read_line")
        return true
      when {"Tcp", "writeText"}
        emit_static_tcp_write(io, expr)
        return true
      when {"Tcp", "tryWriteText"}
        emit_static_tcp_try_write(io, expr)
        return true
      when {"Tcp", "close"}
        emit_static_tcp_close(io, expr, "close_socket")
        return true
      when {"Tcp", "tryClose"}
        emit_static_tcp_try_close(io, expr, "close_socket")
        return true
      when {"Tcp", "accept"}
        emit_static_tcp_accept(io, expr)
        return true
      when {"Tcp", "closeListener"}
        emit_static_tcp_close(io, expr, "close_listener")
        return true
      when {"Tcp", "tryCloseListener"}
        emit_static_tcp_try_close(io, expr, "close_listener")
        return true
      when {"Env", "get"}
        emit_static_env_get(io, expr)
        return true
      when {"Env", "getOr"}
        emit_static_env_get_or(io, expr)
        return true
      when {"Env", "has"}
        emit_static_env_has(io, expr)
        return true
      when {"Env", "args"}
        emit_static_process_args(io)
        return true
      when {"Env", "currentDirectory"}
        emit_static_env_current_directory(io)
        return true
      when {"Process", "args"}
        emit_static_process_args(io)
        return true
      when {"Process", "command"}
        emit_static_process_command(io)
        return true
      when {"Process", "exit"}
        emit_static_process_exit(io, expr)
        return true
      when {"System", "os"}
        emit_static_system_os(io)
        return true
      when {"System", "isWindows"}
        emit_static_system_flag(io, "win32")
        return true
      when {"System", "isLinux"}
        emit_static_system_flag(io, "linux")
        return true
      when {"System", "lineSeparator"}
        emit_static_system_line_separator(io)
        return true
      when {"System", "pathSeparator"}
        emit_static_system_path_separator(io)
        return true
      when {"System", "directorySeparator"}
        emit_static_system_directory_separator(io)
        return true
      when {"Random", "nextInt"}
        emit_static_random_next_int(io, expr)
        return true
      when {"Random", "nextIntBetween"}
        emit_static_random_next_int_between(io, expr)
        return true
      when {"Random", "nextBool"}
        emit_static_random_next_bool(io)
        return true
      when {"Clock", "now"}
        emit_offset_date_time_now(io, false)
        return true
      when {"Clock", "utcNow"}
        emit_offset_date_time_now(io, true)
        return true
      when {"Clock", "millis"}
        emit_static_clock_millis(io)
        return true
      when {"Clock", "sleep"}
        emit_static_clock_sleep(io, expr)
        return true
      end

      raise "Runtime intrinsic #{intrinsic.receiver}.#{intrinsic.method_name} has no codegen emitter"
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

    private def emit_static_console_blank_line(io : IO)
      io << "puts"
    end

    private def emit_static_console_read_line(io : IO)
      io << "(::STDIN.gets || \"\")"
    end

    private def emit_static_console_read_line_or(io : IO, expr : AST::MethodCall)
      io << "(::STDIN.gets || "
      emit_expr(io, expr.args[0])
      io << ")"
    end

    private def emit_static_console_try_read_line(io : IO)
      io << "(begin; __emerald_console_line = ::STDIN.gets; if __emerald_console_line; " << crystal_type("Std::Result::Success<String,String>") << ".new(__emerald_console_line); else " << crystal_type("Std::Result::Failure<String,String>") << ".new(\"No console input available\"); end; rescue ex : Exception; " << crystal_type("Std::Result::Failure<String,String>") << ".new(ex.message || \"Console input error\"); end)"
    end

    private def emit_static_console_prompt(io : IO, expr : AST::MethodCall)
      io << "(::STDOUT.print("
      emit_expr(io, expr.args[0])
      io << "); ::STDOUT.flush; ::STDIN.gets || \"\")"
    end

    private def emit_static_console_prompt_or(io : IO, expr : AST::MethodCall)
      io << "(::STDOUT.print("
      emit_expr(io, expr.args[0])
      io << "); ::STDOUT.flush; ::STDIN.gets || "
      emit_expr(io, expr.args[1])
      io << ")"
    end

    private def emit_static_console_confirm(io : IO, expr : AST::MethodCall)
      emit_static_console_confirm_with_fallback(io, expr, "false")
    end

    private def emit_static_console_confirm_or(io : IO, expr : AST::MethodCall)
      fallback = String.build { |sb| emit_expr(sb, expr.args[1]) }
      emit_static_console_confirm_with_fallback(io, expr, fallback)
    end

    private def emit_static_console_confirm_with_fallback(io : IO, expr : AST::MethodCall, fallback : String)
      io << "(begin; ::STDOUT.print("
      emit_expr(io, expr.args[0])
      io << "); ::STDOUT.flush; __emerald_console_line = ::STDIN.gets; if __emerald_console_line; __emerald_console_answer = __emerald_console_line.strip.downcase; __emerald_console_answer == \"y\" || __emerald_console_answer == \"yes\" || __emerald_console_answer == \"true\"; else "
      io << fallback
      io << "; end; end)"
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

    private def emit_static_path_current(io : IO)
      io << crystal_type("Std::Io::Path") << ".new(::Dir.current)"
    end

    private def emit_static_path_join(io : IO, expr : AST::MethodCall)
      io << "::File.join("
      emit_expr(io, expr.args[0])
      io << ", "
      emit_expr(io, expr.args[1])
      io << ")"
    end

    private def emit_static_path_single(io : IO, expr : AST::MethodCall, method_name : String)
      io << "::File." << method_name << "("
      emit_expr(io, expr.args[0])
      io << ")"
    end

    private def emit_static_file_read_text(io : IO, expr : AST::MethodCall)
      io << "::File.read("
      emit_expr(io, expr.args[0])
      io << ")"
    end

    private def emit_static_file_read_lines(io : IO, expr : AST::MethodCall)
      io << "::File.read_lines("
      emit_expr(io, expr.args[0])
      io << ")"
    end

    private def emit_static_file_write_text(io : IO, expr : AST::MethodCall)
      io << "::File.write("
      emit_expr(io, expr.args[0])
      io << ", "
      emit_expr(io, expr.args[1])
      io << ")"
    end

    private def emit_static_file_append_text(io : IO, expr : AST::MethodCall)
      io << "(::File.open("
      emit_expr(io, expr.args[0])
      io << ", \"a\") { |__emerald_file| __emerald_file << "
      emit_expr(io, expr.args[1])
      io << " }; nil)"
    end

    private def emit_static_file_try_read_text(io : IO, expr : AST::MethodCall)
      io << "(begin; " << crystal_type("Std::Result::Success<String,String>") << ".new(::File.read("
      emit_expr(io, expr.args[0])
      io << ")); rescue ex : Exception; " << crystal_type("Std::Result::Failure<String,String>") << ".new(ex.message || \"IO error\"); end)"
    end

    private def emit_static_file_try_write_text(io : IO, expr : AST::MethodCall)
      io << "(begin; ::File.write("
      emit_expr(io, expr.args[0])
      io << ", "
      emit_expr(io, expr.args[1])
      io << "); " << crystal_type("Std::Result::Success<Bool,String>") << ".new(true); rescue ex : Exception; " << crystal_type("Std::Result::Failure<Bool,String>") << ".new(ex.message || \"IO error\"); end)"
    end

    private def emit_static_file_try_append_text(io : IO, expr : AST::MethodCall)
      io << "(begin; ::File.open("
      emit_expr(io, expr.args[0])
      io << ", \"a\") { |__emerald_file| __emerald_file << "
      emit_expr(io, expr.args[1])
      io << " }; " << crystal_type("Std::Result::Success<Bool,String>") << ".new(true); rescue ex : Exception; " << crystal_type("Std::Result::Failure<Bool,String>") << ".new(ex.message || \"IO error\"); end)"
    end

    private def emit_static_file_predicate(io : IO, expr : AST::MethodCall, method_name : String)
      io << "::File." << method_name << "("
      emit_expr(io, expr.args[0])
      io << ")"
    end

    private def emit_static_file_directory_predicate(io : IO, expr : AST::MethodCall)
      io << "::Dir.exists?("
      emit_expr(io, expr.args[0])
      io << ")"
    end

    private def emit_static_file_delete(io : IO, expr : AST::MethodCall)
      io << "(begin; if ::File.exists?("
      emit_expr(io, expr.args[0])
      io << "); ::File.delete("
      emit_expr(io, expr.args[0])
      io << "); true; else false; end; rescue ex : Exception; false; end)"
    end

    private def emit_static_file_size(io : IO, expr : AST::MethodCall)
      io << "(::File.exists?("
      emit_expr(io, expr.args[0])
      io << ") ? ::File.size("
      emit_expr(io, expr.args[0])
      io << ").to_i64 : 0_i64)"
    end

    private def emit_static_directory_predicate(io : IO, expr : AST::MethodCall)
      io << "::Dir.exists?("
      emit_expr(io, expr.args[0])
      io << ")"
    end

    private def emit_static_directory_create(io : IO, expr : AST::MethodCall)
      io << "(begin; ::Dir.mkdir_p("
      emit_expr(io, expr.args[0])
      io << "); true; rescue ex : Exception; false; end)"
    end

    private def emit_static_directory_delete(io : IO, expr : AST::MethodCall)
      io << "(begin; ::Dir.delete("
      emit_expr(io, expr.args[0])
      io << "); true; rescue ex : Exception; false; end)"
    end

    private def emit_static_directory_list(io : IO, expr : AST::MethodCall)
      io << "::Dir.children("
      emit_expr(io, expr.args[0])
      io << ")"
    end

    private def emit_static_tcp_connect(io : IO, expr : AST::MethodCall)
      io << "(begin; __emerald_socket_handle = EmeraldRuntimeSocket.connect("
      emit_expr(io, expr.args[0])
      io << ", "
      emit_expr(io, expr.args[1])
      io << "); " << crystal_type("Std::Result::Success<Std::Net::ITcpConnection,String>") << ".new("
      io << crystal_type("Std::Net::TcpConnection") << ".new(__emerald_socket_handle, "
      io << crystal_type("Std::Net::Endpoint") << ".new("
      emit_expr(io, expr.args[0])
      io << ", "
      emit_expr(io, expr.args[1])
      io << "))); rescue ex : Exception; " << crystal_type("Std::Result::Failure<Std::Net::ITcpConnection,String>") << ".new(ex.message || \"TCP connect error\"); end)"
    end

    private def emit_static_tcp_listen(io : IO, expr : AST::MethodCall)
      io << "(begin; __emerald_listener_handle = EmeraldRuntimeSocket.listen("
      emit_expr(io, expr.args[0])
      io << ", "
      emit_expr(io, expr.args[1])
      io << "); " << crystal_type("Std::Result::Success<Std::Net::ITcpListener,String>") << ".new("
      io << crystal_type("Std::Net::TcpListener") << ".new(__emerald_listener_handle, "
      io << crystal_type("Std::Net::Endpoint") << ".new("
      emit_expr(io, expr.args[0])
      io << ", "
      emit_expr(io, expr.args[1])
      io << "))); rescue ex : Exception; " << crystal_type("Std::Result::Failure<Std::Net::ITcpListener,String>") << ".new(ex.message || \"TCP listen error\"); end)"
    end

    private def emit_static_tcp_handle_predicate(io : IO, expr : AST::MethodCall, method_name : String)
      io << "EmeraldRuntimeSocket." << method_name << "("
      emit_expr(io, expr.args[0])
      io << ")"
    end

    private def emit_static_tcp_handle_string(io : IO, expr : AST::MethodCall, method_name : String)
      io << "EmeraldRuntimeSocket." << method_name << "("
      emit_expr(io, expr.args[0])
      io << ")"
    end

    private def emit_static_tcp_try_read(io : IO, expr : AST::MethodCall, method_name : String)
      io << "(begin; " << crystal_type("Std::Result::Success<String,String>") << ".new(EmeraldRuntimeSocket." << method_name << "("
      emit_expr(io, expr.args[0])
      io << ")); rescue ex : Exception; " << crystal_type("Std::Result::Failure<String,String>") << ".new(ex.message || \"TCP read error\"); end)"
    end

    private def emit_static_tcp_write(io : IO, expr : AST::MethodCall)
      io << "EmeraldRuntimeSocket.write_text("
      emit_expr(io, expr.args[0])
      io << ", "
      emit_expr(io, expr.args[1])
      io << ")"
    end

    private def emit_static_tcp_try_write(io : IO, expr : AST::MethodCall)
      io << "(begin; " << crystal_type("Std::Result::Success<Bool,String>") << ".new(EmeraldRuntimeSocket.write_text("
      emit_expr(io, expr.args[0])
      io << ", "
      emit_expr(io, expr.args[1])
      io << ")); rescue ex : Exception; " << crystal_type("Std::Result::Failure<Bool,String>") << ".new(ex.message || \"TCP write error\"); end)"
    end

    private def emit_static_tcp_close(io : IO, expr : AST::MethodCall, method_name : String)
      io << "EmeraldRuntimeSocket." << method_name << "("
      emit_expr(io, expr.args[0])
      io << ")"
    end

    private def emit_static_tcp_try_close(io : IO, expr : AST::MethodCall, method_name : String)
      io << "(begin; " << crystal_type("Std::Result::Success<Bool,String>") << ".new(EmeraldRuntimeSocket." << method_name << "("
      emit_expr(io, expr.args[0])
      io << ")); rescue ex : Exception; " << crystal_type("Std::Result::Failure<Bool,String>") << ".new(ex.message || \"TCP close error\"); end)"
    end

    private def emit_static_tcp_accept(io : IO, expr : AST::MethodCall)
      io << "(begin; __emerald_socket_handle = EmeraldRuntimeSocket.accept("
      emit_expr(io, expr.args[0])
      io << "); " << crystal_type("Std::Result::Success<Std::Net::ITcpConnection,String>") << ".new("
      io << crystal_type("Std::Net::TcpConnection") << ".new(__emerald_socket_handle, "
      io << crystal_type("Std::Net::Endpoint") << ".new(\"accepted\", 0_i64))); rescue ex : Exception; " << crystal_type("Std::Result::Failure<Std::Net::ITcpConnection,String>") << ".new(ex.message || \"TCP accept error\"); end)"
    end

    private def emit_static_http_get(io : IO, expr : AST::MethodCall)
      io << "(begin; __emerald_http_response = HTTP::Client.get("
      emit_expr(io, expr.args[0])
      io << "); " << crystal_type("Std::Result::Success<Std::Http::IHttpResponse,String>") << ".new("
      emit_http_response_from_native(io)
      io << "); rescue ex : Exception; " << crystal_type("Std::Result::Failure<Std::Http::IHttpResponse,String>") << ".new(ex.message || \"HTTP error\"); end)"
    end

    private def emit_static_http_post_text(io : IO, expr : AST::MethodCall)
      io << "(begin; __emerald_http_response = HTTP::Client.post("
      emit_expr(io, expr.args[0])
      io << ", body: "
      emit_expr(io, expr.args[1])
      io << "); " << crystal_type("Std::Result::Success<Std::Http::IHttpResponse,String>") << ".new("
      emit_http_response_from_native(io)
      io << "); rescue ex : Exception; " << crystal_type("Std::Result::Failure<Std::Http::IHttpResponse,String>") << ".new(ex.message || \"HTTP error\"); end)"
    end

    private def emit_http_response_from_native(io : IO)
      io << crystal_type("Std::Http::HttpResponse") << ".new(__emerald_http_response.status_code.to_i64, __emerald_http_response.status_message || \"\", __emerald_http_response.body)"
    end


    private def emit_static_env_get(io : IO, expr : AST::MethodCall)
      io << "(ENV["
      emit_expr(io, expr.args[0])
      io << "]? || \"\")"
    end

    private def emit_static_env_get_or(io : IO, expr : AST::MethodCall)
      io << "(ENV["
      emit_expr(io, expr.args[0])
      io << "]? || "
      emit_expr(io, expr.args[1])
      io << ")"
    end

    private def emit_static_env_has(io : IO, expr : AST::MethodCall)
      io << "ENV.has_key?("
      emit_expr(io, expr.args[0])
      io << ")"
    end

    private def emit_static_env_current_directory(io : IO)
      io << "::Dir.current"
    end

    private def emit_static_process_args(io : IO)
      io << "ARGV.map(&.to_s)"
    end

    private def emit_static_process_command(io : IO)
      io << "PROGRAM_NAME"
    end

    private def emit_static_process_exit(io : IO, expr : AST::MethodCall)
      io << "(exit(("
      emit_expr(io, expr.args[0])
      io << ").to_i32); nil)"
    end

    private def emit_static_system_os(io : IO)
      io << "({% if flag?(:win32) %}\"windows\"{% elsif flag?(:linux) %}\"linux\"{% elsif flag?(:darwin) %}\"macos\"{% else %}\"unknown\"{% end %})"
    end

    private def emit_static_system_flag(io : IO, flag_name : String)
      io << "({% if flag?(:" << flag_name << ") %}true{% else %}false{% end %})"
    end

    private def emit_static_system_line_separator(io : IO)
      io << "({% if flag?(:win32) %}\"\\r\\n\"{% else %}\"\\n\"{% end %})"
    end

    private def emit_static_system_path_separator(io : IO)
      io << "({% if flag?(:win32) %}\";\"{% else %}\":\"{% end %})"
    end

    private def emit_static_system_directory_separator(io : IO)
      io << "({% if flag?(:win32) %}\"\\\\\"{% else %}\"/\"{% end %})"
    end

    private def emit_static_random_next_int(io : IO, expr : AST::MethodCall)
      io << "(begin; __emerald_random_max = "
      emit_expr(io, expr.args[0])
      io << "; __emerald_random_max <= 0_i64 ? 0_i64 : ::Random.rand(__emerald_random_max.to_i).to_i64; end)"
    end

    private def emit_static_random_next_int_between(io : IO, expr : AST::MethodCall)
      io << "(begin; __emerald_random_min = "
      emit_expr(io, expr.args[0])
      io << "; __emerald_random_max = "
      emit_expr(io, expr.args[1])
      io << "; if __emerald_random_max <= __emerald_random_min; __emerald_random_min; else __emerald_random_min + ::Random.rand((__emerald_random_max - __emerald_random_min + 1_i64).to_i).to_i64; end; end)"
    end

    private def emit_static_random_next_bool(io : IO)
      io << "(::Random.rand(2) == 1)"
    end

    private def emit_static_clock_millis(io : IO)
      io << "::Time.utc.to_unix_ms.to_i64"
    end

    private def emit_static_clock_sleep(io : IO, expr : AST::MethodCall)
      io << "(sleep(("
      emit_expr(io, expr.args[0])
      io << ").toMillis().to_f64 / 1000.0); nil)"
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
