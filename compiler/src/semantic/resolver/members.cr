require "../resolver"

module Emerald
  class Resolver
    private def collect_class_members(decl : AST::Node)
      case decl
      when AST::ClassDecl
        info = @registry[fqn_of(decl.name, decl.namespace)].not_nil!
        saved = @current_type_params
        @current_type_params = decl.type_params
        info.base = decl.base ? resolve_type_name(decl.base.not_nil!, decl.namespace, decl.line, decl.col) : nil
        info.interfaces = decl.interfaces.map { |i| resolve_type_usage_name(i, decl.namespace, decl.line, decl.col) }

        decl.fields.each do |f|
          info.fields[f.name] = FieldInfo.new(f.name, type_ref_to_fqn(f.type_ref, decl.namespace), f.visibility)
        end
        decl.methods.each do |m|
          declared_ret = type_ref_to_fqn(m.return_type, decl.namespace)
          effective_ret = m.is_async ? "Fiber<#{declared_ret}>" : declared_ret
          mi = MethodInfo.new(
            m.name,
            m.params.map { |p| type_ref_to_fqn(p.type_ref, decl.namespace) },
            effective_ret,
            m.visibility,
            m.is_abstract
          )
          mi.deprecated_message = m.deprecated_message
          info.methods[m.name] = mi
        end

        if decl.is_data && decl.constructors.empty?
          info.constructors << ConstructorInfo.new(
            decl.fields.map { |f| type_ref_to_fqn(f.type_ref, decl.namespace) },
            AST::Visibility::Public
          )
        end

        decl.constructors.each do |c|
          info.constructors << ConstructorInfo.new(
            c.params.map { |p| type_ref_to_fqn(p.type_ref, decl.namespace) },
            c.visibility
          )
        end

        if info.constructors.empty?
          empty = [] of String
          info.constructors << ConstructorInfo.new(empty, AST::Visibility::Public)
        end

        if decl.is_data
          info.methods["equals"] = MethodInfo.new(
            "equals", [info.fqn], "Bool", AST::Visibility::Public, false
          )
          info.methods["copy"] = MethodInfo.new(
            "copy",
            decl.fields.map { |f| type_ref_to_fqn(f.type_ref, decl.namespace) },
            info.fqn,
            AST::Visibility::Public, false
          )
        end
        @current_type_params = saved
      when AST::InterfaceDecl
        info = @registry[fqn_of(decl.name, decl.namespace)].not_nil!
        info.interfaces = decl.extends_interfaces.map { |i| resolve_type_usage_name(i, decl.namespace, decl.line, decl.col) }
        decl.methods.each do |m|
          info.methods[m.name] = MethodInfo.new(
            m.name,
            m.params.map { |p| type_ref_to_fqn(p.type_ref, decl.namespace) },
            type_ref_to_fqn(m.return_type, decl.namespace),
            m.visibility,
            m.body.nil?
          )
        end
      end
    end

    private def type_ref_to_fqn(ref : AST::TypeRef, current_ns : String) : String
      case ref
      when AST::NamedType
        nt = ref.as(AST::NamedType)
        return nt.name if BUILTIN_TYPES.includes?(nt.name)
        return nt.name if RESERVED_NAMES.includes?(nt.name)
        return nt.name if BUILTIN_CONTAINER_NAMES.includes?(nt.name)
        return nt.name if MACRO_AST_TYPES.includes?(nt.name)
        return nt.name if @current_type_params.includes?(nt.name)
        resolve_type_name(nt.name, current_ns, nt.line, nt.col)
      when AST::GenericType
        gt = ref.as(AST::GenericType)
        base_fqn = if BUILTIN_TYPES.includes?(gt.name) ||
                       RESERVED_NAMES.includes?(gt.name) ||
                       BUILTIN_CONTAINER_NAMES.includes?(gt.name) ||
                       @current_type_params.includes?(gt.name)
                     gt.name
                   else
                     resolve_type_name(gt.name, current_ns, gt.line, gt.col)
                   end
        args = gt.type_args.map { |a| type_ref_to_fqn(a, current_ns) }.join(",")
        "#{base_fqn}<#{args}>"
      when AST::FunctionType
        ft = ref.as(AST::FunctionType)
        params = ft.param_types.map { |p| type_ref_to_fqn(p, current_ns) }.join(",")
        "Fn(#{params}):#{type_ref_to_fqn(ft.return_type, current_ns)}"
      else
        "Unknown"
      end
    end

    private def resolve_type_usage_name(name : String, current_ns : String, line : Int32, col : Int32) : String
      base = type_usage_base_name(name)
      args = type_usage_arguments(name)
      base_fqn = resolve_type_name(base, current_ns, line, col)

      return base_fqn if args.empty?

      resolved_args = args.map { |arg| resolve_type_usage_name(arg, current_ns, line, col) }.join(",")
      "#{base_fqn}<#{resolved_args}>"
    end

    private def type_usage_base_name(name : String) : String
      index = name.index("<")
      return name unless index

      name[0...index.not_nil!]
    end

    private def type_usage_arguments(name : String) : Array(String)
      start = name.index("<")
      return [] of String unless start && name.ends_with?(">")

      inner = name[(start.not_nil! + 1)...-1]
      split_type_usage_arguments(inner)
    end

    private def split_type_usage_arguments(value : String) : Array(String)
      result = [] of String
      depth = 0
      buffer = String.build do |io|
        value.each_char do |char|
          case char
          when '<'
            depth += 1
            io << char
          when '>'
            depth -= 1
            io << char
          when ','
            if depth == 0
              result << io.to_s.strip
              io.clear
            else
              io << char
            end
          else
            io << char
          end
        end
        result << io.to_s.strip
      end
      result.reject(&.empty?)
    end

    BUILTIN_TYPES = ["Int", "Float", "Bool", "Char", "String", "Void", "Any", "Range"]

    private def resolve_type_name(name : String, current_ns : String, line : Int32, col : Int32) : String
      return name if BUILTIN_TYPES.includes?(name)
      return name if RESERVED_NAMES.includes?(name)
      return name if BUILTIN_CONTAINER_NAMES.includes?(name)
      return name if MACRO_AST_TYPES.includes?(name)
      return name if @current_type_params.includes?(name)
      if name.includes?("::")
        segments = name.split("::")
        type_name = segments.pop
        return @namespace_resolver.resolve_type_qualified(segments, type_name, line, col)
      end

      @namespace_resolver.resolve_type_simple(name, current_ns, line, col)
    end

  end
end
