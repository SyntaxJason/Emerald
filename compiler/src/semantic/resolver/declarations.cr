require "../resolver"

module Emerald
  class Resolver
    private def collect_declaration(decl : AST::Node, ns : String)
      case decl
      when AST::FunctionDecl
        check_reserved!(decl.name, decl.line, decl.col)
        decl_ns = decl.namespace.empty? ? ns : decl.namespace
        fqn = fqn_of(decl.name, decl_ns)
        param_types = decl.params.map { |p| TypeSystem.type_ref_name(p.type_ref) }
        ret = TypeSystem.type_ref_name(decl.return_type)
        sym = FunctionSymbol.new(decl.name, param_types, ret, fqn)
        unless @global_scope.symbols.has_key?(decl.name)
          @global_scope.declare(decl.name, sym, decl.line, decl.col)
        end
        @namespace_resolver.add_function(fqn, sym)
      when AST::ClassDecl
        check_reserved!(decl.name, decl.line, decl.col)
        decl_ns = decl.namespace.empty? ? ns : decl.namespace
        fqn = fqn_of(decl.name, decl_ns)
        info = ClassInfo.new(decl.name, fqn, decl.is_data, decl.is_abstract, false)
        info.type_params = decl.type_params.dup
        @registry.register(info, decl.line, decl.col)
        type_sym = TypeSymbol.new(decl.name, decl.is_data ? "data" : "class", fqn)
        unless @global_scope.symbols.has_key?(decl.name)
          @global_scope.declare(decl.name, type_sym, decl.line, decl.col)
        end
      when AST::InterfaceDecl
        check_reserved!(decl.name, decl.line, decl.col)
        decl_ns = decl.namespace.empty? ? ns : decl.namespace
        fqn = fqn_of(decl.name, decl_ns)
        info = ClassInfo.new(decl.name, fqn, false, false, true)
        info.type_params = decl.type_params.dup
        @registry.register(info, decl.line, decl.col)
        type_sym = TypeSymbol.new(decl.name, "interface", fqn)
        unless @global_scope.symbols.has_key?(decl.name)
          @global_scope.declare(decl.name, type_sym, decl.line, decl.col)
        end
      when AST::AliasDecl
        target_fqn = decl.target.to_s
        @namespace_resolver.add_alias(decl.name, target_fqn, decl.line, decl.col)
      when AST::MacroDecl
        if prog = @program
          check_macro_declaration!(decl, prog.macro_registry)
          prog.macro_registry.register(decl)
        end
      end
    end

    private def check_macro_declaration!(decl : AST::MacroDecl, macro_registry : AST::MacroRegistry)
      if existing = macro_registry.find(decl.name)
        return if same_macro_declaration?(existing, decl)

        raise ResolveError.new(
          "Macro '#{decl.name}' is already defined at #{existing.line}:#{existing.col}",
          decl.line,
          decl.col)
      end

      if BUILTIN_ANNOTATION_NAMES.includes?(decl.name)
        raise ResolveError.new(
          "Macro '#{decl.name}' conflicts with built-in annotation '@#{decl.name}'",
          decl.line,
          decl.col)
      end

      if RESERVED_NAMES.includes?(decl.name) ||
         BUILTIN_CONTAINER_NAMES.includes?(decl.name) ||
         MACRO_AST_TYPES.includes?(decl.name) ||
         MACRO_BUILDER_NAMES.includes?(decl.name)
        raise ResolveError.new(
          "Macro '#{decl.name}' conflicts with a reserved Emerald compiler name",
          decl.line,
          decl.col)
      end
    end

    private def same_macro_declaration?(existing : AST::MacroDecl, current : AST::MacroDecl) : Bool
      return true if existing.same?(current)

      existing.name == current.name &&
        existing.target == current.target &&
        existing.line == current.line &&
        existing.col == current.col
    end


    private def check_reserved!(name : String, line : Int32, col : Int32)
      if RESERVED_NAMES.includes?(name)
        raise ResolveError.new("'#{name}' is a reserved name and cannot be redefined", line, col)
      end
    end

  end
end
