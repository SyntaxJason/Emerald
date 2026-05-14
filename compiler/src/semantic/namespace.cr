require "../frontend/ast"
require "./scope"
require "./registry"

module Emerald
  RESERVED_NAMES = ["Result", "Ok", "Err"]
  BUILTIN_CONTAINER_NAMES = ["List", "Map", "Set", "Fiber", "Thread", "VirtualThread", "Channel", "Mutex"]
  MACRO_AST_TYPES = ["MethodAST", "ClassAST", "ParamAST", "FieldAST", "BlockAST", "StatementAST", "ExpressionAST"]
  DEFAULT_ROOT_NAMESPACE = "Emerald"

  class NamespaceResolver
    getter registry : ClassRegistry
    getter functions_by_fqn : Hash(String, FunctionSymbol)
    getter aliases : Hash(String, String)

    def initialize(@registry : ClassRegistry)
      @functions_by_fqn = {} of String => FunctionSymbol
      @aliases = {} of String => String
    end

    def add_function(fqn : String, sym : FunctionSymbol)
      @functions_by_fqn[fqn] = sym
    end

    def add_alias(name : String, target_fqn : String, line : Int32, col : Int32)
      if existing = @aliases[name]?
        return if existing == target_fqn

        raise ResolveError.new(
          "Import alias '#{name}' already points to #{existing}; cannot also point to #{target_fqn}. Use 'use #{target_fqn} as ...'",
          line,
          col)
      end

      @aliases[name] = target_fqn
    end

    def resolve_type_simple(name : String, current_ns : String, line : Int32, col : Int32) : String
      if RESERVED_NAMES.includes?(name)
        return name
      end
      if BUILTIN_CONTAINER_NAMES.includes?(name)
        return name
      end
      if MACRO_AST_TYPES.includes?(name)
        return name
      end

      local_fqn = current_ns.empty? ? name : "#{current_ns}::#{name}"
      local_type = @registry[local_fqn] ? local_fqn : nil

      if target = @aliases[name]?
        if local_type && local_type != target
          raise ResolveError.new(
            "Imported alias '#{name}' points to #{target}, but local type #{local_type} exists. Use 'use #{target} as ...' to avoid the conflict.",
            line,
            col)
        end

        unless @registry[target]
          raise ResolveError.new("Imported type '#{target}' for alias '#{name}' does not exist", line, col)
        end

        return target
      end

      return local_type if local_type

      candidates = @registry.resolve_simple(name)
      case candidates.size
      when 0
        raise ResolveError.new("Unknown type '#{name}'", line, col)
      when 1
        candidates[0]
      else
        raise ResolveError.new(
          "Ambiguous type '#{name}' - matches: #{candidates.join(", ")}. Use 'use ... as ...' or a fully-qualified name.",
          line, col
        )
      end
    end

    def resolve_type_qualified(segments : Array(String), name : String, line : Int32, col : Int32) : String
      fqn = "#{segments.join("::")}::#{name}"
      info = @registry[fqn]
      unless info
        raise ResolveError.new("Unknown type '#{fqn}'", line, col)
      end
      fqn
    end

    def resolve_function_simple(name : String, current_ns : String, line : Int32, col : Int32) : FunctionSymbol?
      if sym = @functions_by_fqn[name]?
        return sym
      end
      candidates = @functions_by_fqn.keys.select { |fqn| simple_name_of(fqn) == name }
      case candidates.size
      when 0
        nil
      when 1
        @functions_by_fqn[candidates[0]]
      else
        in_current = candidates.find { |c| ns_of(c) == current_ns }
        return @functions_by_fqn[in_current] if in_current
        raise ResolveError.new(
          "Ambiguous function '#{name}' - exists in: #{candidates.join(", ")}.",
          line, col
        )
      end
    end

    def resolve_function_qualified(segments : Array(String), name : String, line : Int32, col : Int32) : FunctionSymbol?
      fqn = "#{segments.join("::")}::#{name}"
      if direct = @functions_by_fqn[fqn]?
        return direct
      end
      suffix = "::#{fqn}"
      candidates = @functions_by_fqn.keys.select { |k| k.ends_with?(suffix) }
      case candidates.size
      when 0 then nil
      when 1 then @functions_by_fqn[candidates[0]]
      else
        raise ResolveError.new(
          "Ambiguous function '#{fqn}' - matches: #{candidates.join(", ")}.",
          line, col
        )
      end
    end

    def ns_of(fqn : String) : String
      idx = fqn.rindex("::")
      idx ? fqn[0...idx] : ""
    end

    def simple_name_of(fqn : String) : String
      idx = fqn.rindex("::")
      idx ? fqn[(idx + 2)..] : fqn
    end
  end
end
