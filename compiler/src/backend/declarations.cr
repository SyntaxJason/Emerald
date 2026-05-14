module Emerald
  class Codegen
    def emit_interface(io : IO, decl : AST::InterfaceDecl)
      mangled = mangle_fqn("#{decl.namespace}::#{decl.name}")
      io << "module " << mangled << "\n"
      @indent += 1
      decl.methods.each do |m|
        next unless m.is_default
        body = m.body
        next if body.nil?
        emit_method(io, m, body)
      end
      @indent -= 1
      io << "end\n\n"
    end

    def emit_class(io : IO, decl : AST::ClassDecl)
      mangled = mangle_fqn("#{decl.namespace}::#{decl.name}")
      io << "class " << mangled
      unless decl.type_params.empty?
        io << "(" << decl.type_params.join(", ") << ")"
      end
      if base = decl.base
        base_fqn = base.includes?("::") ? base : @resolver.registry.resolve_simple(base).first
        io << " < " << mangle_fqn(base_fqn)
      end
      io << "\n"
      @indent += 1

      decl.interfaces.each do |iface|
        iface_fqn = iface.includes?("::") ? iface : @resolver.registry.resolve_simple(iface).first
        indent(io); io << "include " << mangle_fqn(iface_fqn) << "\n"
      end

      decl.fields.each do |f|
        indent(io)
        io << "@" << f.name << " : " << crystal_type(field_type_fqn(f, decl.namespace))
        if init = f.initializer
          io << " = "
          emit_expr(io, init)
        end
        io << "\n"
      end
      if decl.needs_lock_field
        indent(io); io << "@__lock : Mutex = Mutex.new\n"
      end
      io << "\n" unless decl.fields.empty? && !decl.needs_lock_field

      decl.fields.each do |f|
        indent(io); io << "property " << f.name << " : " << crystal_type(field_type_fqn(f, decl.namespace)) << "\n"
      end
      io << "\n" unless decl.fields.empty?

      if decl.is_data && decl.constructors.empty?
        emit_data_constructor(io, decl)
      else
        decl.constructors.each { |c| emit_constructor(io, c) }
      end

      decl.methods.each do |m|
        next if m.is_abstract
        body = m.body
        next if body.nil?
        emit_method(io, m, body)
      end

      if decl.is_data
        emit_data_copy(io, decl, mangled)
        emit_data_equals(io, decl, mangled)
        emit_data_to_string(io, decl)
      end

      @indent -= 1
      io << "end\n\n"
    end

    private def field_type_fqn(f : AST::FieldDecl, current_ns : String) : String
      case f.type_ref
      when AST::NamedType
        nt = f.type_ref.as(AST::NamedType)
        return nt.name if Resolver::BUILTIN_TYPES.includes?(nt.name)
        return nt.name if RESERVED_NAMES.includes?(nt.name)
        candidates = @resolver.registry.resolve_simple(nt.name)
        candidates.empty? ? nt.name : candidates.first
      else
        type_ref_name(f.type_ref)
      end
    end

    private def emit_constructor(io : IO, ctor : AST::ConstructorDecl)
      indent(io); io << "def initialize("
      ctor.params.each_with_index do |p, i|
        io << ", " if i > 0
        io << p.name << " : " << crystal_type(type_ref_name(p.type_ref))
      end
      io << ")\n"
      @indent += 1
      ctor.body.statements.each { |s| emit_stmt(io, s) }
      @indent -= 1
      indent(io); io << "end\n\n"
    end

  end
end

require "./declarations/data"
require "./declarations/methods"
