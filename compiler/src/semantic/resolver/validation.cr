require "../resolver"

module Emerald
  class Resolver
    private def validate_base_and_interfaces(decl : AST::ClassDecl)
      if base = decl.base
        info = @registry[resolve_type_name(base, decl.namespace, decl.line, decl.col)]
        unless info
          raise ResolveError.new("Unknown base class '#{base}'", decl.line, decl.col)
        end
        if info.is_interface
          raise ResolveError.new("Cannot extend interface '#{base}' (use implements)", decl.line, decl.col)
        end
      end
      decl.interfaces.each do |iface|
        iface_usage = resolve_type_usage_name(iface, decl.namespace, decl.line, decl.col)
        info = @registry[type_usage_base_name(iface_usage)]
        unless info
          raise ResolveError.new("Unknown interface '#{iface}'", decl.line, decl.col)
        end
        unless info.is_interface
          raise ResolveError.new("'#{iface}' is not an interface", decl.line, decl.col)
        end
      end
    end

    private def validate_interface_implementations(decl : AST::ClassDecl)
      return if decl.is_abstract

      class_fqn = fqn_of(decl.name, decl.namespace)

      decl.interfaces.each do |iface|
        iface_usage = resolve_type_usage_name(iface, decl.namespace, decl.line, decl.col)
        bindings = interface_type_bindings(iface_usage)
        validate_interface_methods_implemented(decl, class_fqn, iface_usage, bindings)
      end
    end

    private def validate_interface_methods_implemented(decl : AST::ClassDecl, class_fqn : String, iface_usage : String, bindings : Hash(String, String))
      iface_fqn = type_usage_base_name(iface_usage)
      iface_info = @registry[iface_fqn]
      return unless iface_info

      iface_info.interfaces.each do |parent_iface|
        parent_usage = substitute_type_params(parent_iface, bindings)
        parent_bindings = interface_type_bindings(parent_usage)
        validate_interface_methods_implemented(decl, class_fqn, parent_usage, parent_bindings)
      end

      iface_info.methods.each_value do |required_method|
        next unless required_method.is_abstract

        implemented_method = lookup_class_hierarchy_method(class_fqn, required_method.name)

        unless implemented_method
          raise ResolveError.new(
            "Class '#{decl.name}' must implement '#{required_method.name}' from interface '#{iface_info.name}'",
            decl.line,
            decl.col)
        end

        unless method_signature_matches?(implemented_method, required_method, bindings)
          raise ResolveError.new(
            "Class '#{decl.name}' method '#{required_method.name}' does not match interface '#{iface_info.name}' signature",
            decl.line,
            decl.col)
        end
      end
    end

    private def lookup_class_hierarchy_method(class_fqn : String, method_name : String) : MethodInfo?
      class_info = @registry[class_fqn]
      return nil unless class_info

      if method = class_info.methods[method_name]?
        return method unless method.is_abstract
      end

      if base = class_info.base
        return lookup_class_hierarchy_method(base, method_name)
      end

      nil
    end

    private def method_signature_matches?(actual : MethodInfo, expected : MethodInfo, bindings : Hash(String, String)) : Bool
      return false unless actual.return_type == substitute_type_params(expected.return_type, bindings)
      return false unless actual.param_types.size == expected.param_types.size

      actual.param_types.each_with_index do |actual_type, index|
        return false unless actual_type == substitute_type_params(expected.param_types[index], bindings)
      end

      true
    end

    private def interface_type_bindings(iface_usage : String) : Hash(String, String)
      iface_fqn = type_usage_base_name(iface_usage)
      iface_info = @registry[iface_fqn]
      return {} of String => String unless iface_info

      args = type_usage_arguments(iface_usage)
      bindings = {} of String => String

      iface_info.type_params.each_with_index do |param, index|
        next unless arg = args[index]?

        bindings[param] = arg
      end

      bindings
    end

    private def substitute_type_params(type_name : String, bindings : Hash(String, String)) : String
      if replacement = bindings[type_name]?
        return replacement
      end

      args = type_usage_arguments(type_name)
      return type_name if args.empty?

      base = type_usage_base_name(type_name)
      replaced_args = args.map { |arg| substitute_type_params(arg, bindings) }.join(",")
      "#{base}<#{replaced_args}>"
    end

    private def validate_overrides(decl : AST::ClassDecl)
      decl.methods.each do |m|
        next unless m.is_override
        found = false
        if base = decl.base
          base_fqn = resolve_type_name(base, decl.namespace, decl.line, decl.col)
          if @registry.lookup_method(base_fqn, m.name)
            found = true
          end
        end
        unless found
          decl.interfaces.each do |iface|
            iface_fqn = resolve_type_name(iface, decl.namespace, decl.line, decl.col)
            if @registry.lookup_method(iface_fqn, m.name)
              found = true
              break
            end
          end
        end
        unless found
          raise ResolveError.new(
            "@Override on method '#{m.name}' but no matching method found in base class or interfaces",
            m.line, m.col
          )
        end
      end
    end

  end
end
