require "../expressions"

module Emerald
  class Codegen
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
