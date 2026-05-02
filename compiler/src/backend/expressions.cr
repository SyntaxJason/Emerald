require "./base"
require "../semantic/builtin_functions"

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

    private def emit_call(io : IO, expr : AST::CallExpr)
      sym = @resolver.global_scope.lookup(expr.callee)
      is_lambda_var = sym.is_a?(VarSymbol) && sym.as(VarSymbol).type_name.starts_with?("Fn(")

      target_fqn = if !expr.namespace_path.empty?
                     direct = "#{expr.namespace_path.join("::")}::#{expr.callee}"
                     if @resolver.namespace_resolver.functions_by_fqn.has_key?(direct)
                       direct
                     else
                       suffix = "::#{direct}"
                       match = @resolver.namespace_resolver.functions_by_fqn.keys.find { |k| k.ends_with?(suffix) }
                       match || direct
                     end
                   elsif fn_sym = @resolver.namespace_resolver.functions_by_fqn.values.find { |f| f.name == expr.callee }
                     fn_sym.fqn
                   else
                     expr.callee
                   end

      if !is_lambda_var && (bf = BuiltinFunctions.for_fqn(target_fqn))
        arg_strs = expr.args.map do |arg|
          String.build { |sb| emit_expr(sb, arg) }
        end
        template = bf.crystal_template
        arg_strs.each_with_index do |a, i|
          template = template.gsub("%a#{i}%", a)
        end
        io << template
        return
      end

      name = case expr.callee
             when "println" then "puts"
             when "print"   then "print"
             else
               if target_fqn != expr.callee
                 mangle_fqn(target_fqn)
               else
                 expr.callee
               end
             end
      io << name
      io << ".call" if is_lambda_var
      io << "("
      expr.args.each_with_index do |arg, i|
        io << ", " if i > 0
        emit_expr(io, arg)
      end
      io << ")"
    end

    private def emit_new(io : IO, expr : AST::NewExpr)
      if BUILTIN_CONTAINER_NAMES.includes?(expr.type_name)
        ct = crystal_type(expr.expected_type)
        io << ct << ".new"
        return
      end

      fqn = if expr.namespace_path.empty?
              candidates = @resolver.registry.resolve_simple(expr.type_name)
              candidates.empty? ? expr.type_name : candidates.first
            else
              "#{expr.namespace_path.join("::")}::#{expr.type_name}"
            end

      info = @resolver.registry[fqn]
      if info && !info.type_params.empty?
        ct = if !expr.expected_type.empty?
               crystal_type(expr.expected_type)
             else
               crystal_type(fqn)
             end
        io << ct << ".new("
      else
        io << mangle_fqn(fqn) << ".new("
      end
      expr.args.each_with_index do |arg, i|
        io << ", " if i > 0
        emit_expr(io, arg)
      end
      io << ")"
    end

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

    private def emit_interp(io : IO, expr : AST::StringInterp)
      io << '"'
      expr.parts.each do |part|
        case part
        when AST::InterpText
          io << escape_for_dq(part.value)
        when AST::InterpExpr
          io << '#' << '{'
          emit_expr(io, part.expression)
          io << '}'
        end
      end
      io << '"'
    end

    private def emit_lambda(io : IO, expr : AST::LambdaExpr)
      io << "->("
      expr.params.each_with_index do |p, i|
        io << ", " if i > 0
        io << p.name << " : " << crystal_type(type_ref_name(p.type_ref))
      end
      io << ") {\n"
      @indent += 1
      body = expr.body
      if body.is_a?(AST::Block)
        body.as(AST::Block).statements.each { |s| emit_stmt(io, s) }
      else
        indent(io)
        emit_expr(io, body)
        io << "\n"
      end
      @indent -= 1
      indent(io); io << "}"
    end

    private def emit_method_ref(io : IO, expr : AST::MethodRef)
      if tn = expr.type_name
        candidates = @resolver.registry.resolve_simple(tn)
        type_fqn = candidates.empty? ? tn : candidates.first
        io << "->(__r : " << mangle_fqn(type_fqn) << ") { __r." << expr.method_name << " }"
      elsif recv = expr.receiver
        io << "->{ "
        emit_expr(io, recv)
        io << "." << expr.method_name << " }"
      end
    end
  end
end
