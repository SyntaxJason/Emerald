require "../declarations"

module Emerald
  class Codegen
    private def emit_method(io : IO, m : AST::MethodDecl, body : AST::Block)
      reset_typed_locals

      declared_ret = type_ref_name(m.return_type)
      effective_ret = m.is_async ? "Fiber<#{declared_ret}>" : declared_ret

      indent(io); io << "def "
      io << "self." if m.is_static
      io << crystal_method_name(m.name) << "("
      m.params.each_with_index do |p, i|
        register_typed_local(p.name)
        io << ", " if i > 0
        io << crystal_local_name(p.name) << " : " << crystal_type(type_ref_name(p.type_ref))
      end
      io << ") : " << crystal_type(effective_ret) << "\n"
      @indent += 1

      if m.is_async
        indent(io); io << "EmeraldFiber.spawn {\n"
        @indent += 1
        indent(io); io << "(-> {\n"
        @indent += 1
        if m.is_synchronized
          indent(io); io << "@__lock.synchronize do\n"
          @indent += 1
          body.statements.each { |s| emit_stmt(io, s) }
          @indent -= 1
          indent(io); io << "end\n"
        else
          body.statements.each { |s| emit_stmt(io, s) }
        end
        @indent -= 1
        indent(io); io << "}).call\n"
        @indent -= 1
        indent(io); io << "}\n"
      elsif m.is_synchronized
        indent(io); io << "@__lock.synchronize do\n"
        @indent += 1
        body.statements.each { |s| emit_stmt(io, s) }
        @indent -= 1
        indent(io); io << "end\n"
      else
        body.statements.each { |s| emit_stmt(io, s) }
      end

      @indent -= 1
      indent(io); io << "end\n\n"
    end

    def emit_function(io : IO, fn : AST::FunctionDecl)
      reset_typed_locals

      fqn = fn.namespace.empty? ? fn.name : "#{fn.namespace}::#{fn.name}"
      mangled = mangle_fn_fqn(fqn)
      io << "def " << mangled << "("
      fn.params.each_with_index do |p, i|
        register_typed_local(p.name)
        io << ", " if i > 0
        io << crystal_local_name(p.name) << " : " << crystal_type(type_ref_name(p.type_ref))
      end
      io << ") : " << crystal_type(type_ref_name(fn.return_type)) << "\n"
      @indent += 1
      fn.body.statements.each { |s| emit_stmt(io, s) }
      @indent -= 1
      io << "end\n\n"
    end

  end
end
