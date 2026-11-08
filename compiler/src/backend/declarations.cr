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
        iface_base = base_type_name(iface)
        candidates = iface_base.includes?("::") ? [iface_base] : @resolver.registry.resolve_simple(iface_base)
        iface_fqn = candidates.empty? ? iface_base : candidates.first

        indent(io)
        io << "include " << mangle_fqn(iface_fqn) << "\n"
      end

      decl.fields.each do |f|
        field_type = crystal_type(field_type_fqn(f, decl.namespace))

        indent(io)
        io << "@" << f.name << " : " << field_type << "? = "

        if init = f.initializer
          emit_expr(io, init)
        else
          io << "nil"
        end

        io << "\n"
      end

      if decl.needs_lock_field
        indent(io)
        io << "@__lock : Mutex = Mutex.new\n"
      end

      io << "\n" unless decl.fields.empty? && !decl.needs_lock_field

      decl.fields.each do |f|
        field_type = crystal_type(field_type_fqn(f, decl.namespace))

        indent(io)
        io << "def " << crystal_method_name(f.name) << " : " << field_type << "\n"
        @indent += 1
        indent(io)
        io << "@" << f.name << ".not_nil!\n"
        @indent -= 1
        indent(io)
        io << "end\n\n"

        indent(io)
        io << "def " << crystal_method_name(f.name) << "=(value : " << field_type << ")\n"
        @indent += 1
        indent(io)
        io << "@" << f.name << " = value\n"
        @indent -= 1
        indent(io)
        io << "end\n"
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
        named_type = f.type_ref.as(AST::NamedType)

        return named_type.name if Resolver::BUILTIN_TYPES.includes?(named_type.name)
        return named_type.name if RESERVED_NAMES.includes?(named_type.name)

        candidates = @resolver.registry.resolve_simple(named_type.name)
        candidates.empty? ? named_type.name : candidates.first
      else
        type_ref_name(f.type_ref)
      end
    end

    private def crystal_default_value_for_field(f : AST::FieldDecl, field_type : String) : String
      interface_default = crystal_default_value_for_interface_type(f.type_ref)
      return interface_default unless interface_default.nil?

      crystal_default_value(field_type)
    end

    private def crystal_default_value_for_interface_type(ref : AST::TypeRef) : String?
      case ref
      when AST::GenericType
        generic_type = ref.as(AST::GenericType)
        base_fqn = runtime_type_fqn(generic_type.name)
        args = generic_type.type_args.map { |arg| crystal_type(type_ref_name(arg)) }

        case base_fqn
        when "Std::Collections::IList"
          return "#{mangle_fqn("Std::Collections::ArrayList")}(#{args[0]}).new" if args.size == 1
        when "Std::Collections::ISet"
          return "#{mangle_fqn("Std::Collections::HashSet")}(#{args[0]}).new" if args.size == 1
        when "Std::Collections::IMap"
          return "#{mangle_fqn("Std::Collections::HashMap")}(#{args[0]}, #{args[1]}).new" if args.size == 2
        end
      when AST::NamedType
        named_type = ref.as(AST::NamedType)
        base_fqn = runtime_type_fqn(named_type.name)

        case base_fqn
        when "Std::Http::IHttpHeaders"
          return "#{mangle_fqn("Std::Http::HttpHeaders")}.new"
        when "Std::Json::IJsonValue"
          return "#{mangle_fqn("Std::Json::JsonNull")}.new"
        end
      end

      nil
    end

    private def crystal_default_value(type_name : String) : String
      return "0_i64" if type_name == "Int64"
      return "0_i32" if type_name == "Int32"
      return "0_i16" if type_name == "Int16"
      return "0_i8" if type_name == "Int8"
      return "0_u64" if type_name == "UInt64"
      return "0_u32" if type_name == "UInt32"
      return "0_u16" if type_name == "UInt16"
      return "0_u8" if type_name == "UInt8"
      return "0.0_f64" if type_name == "Float64"
      return "0.0_f32" if type_name == "Float32"
      return "false" if type_name == "Bool"
      return "'\\0'" if type_name == "Char"
      return "\"\"" if type_name == "String"
      return "nil" if type_name == "Nil"
      return "Mutex.new" if type_name == "Mutex"
      return "#{type_name}.new" if type_name.starts_with?("Array(")
      return "#{type_name}.new" if type_name.starts_with?("Set(")
      return "#{type_name}.new" if type_name.starts_with?("Hash(")

      "#{type_name}.allocate"
    end

    private def emit_constructor(io : IO, ctor : AST::ConstructorDecl)
      reset_typed_locals

      indent(io)
      io << "def initialize("

      ctor.params.each_with_index do |p, i|
        register_typed_local(p.name)
        io << ", " if i > 0
        io << crystal_local_name(p.name) << " : " << crystal_type(type_ref_name(p.type_ref))
      end

      io << ")\n"
      @indent += 1

      ctor.body.statements.each { |s| emit_stmt(io, s) }

      @indent -= 1
      indent(io)
      io << "end\n\n"
    end
  end
end

require "./declarations/data"
require "./declarations/methods"
