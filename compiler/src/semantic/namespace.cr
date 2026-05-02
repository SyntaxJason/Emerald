require "../frontend/ast"
require "./scope"
require "./registry"

module Emerald
  RESERVED_NAMES = ["Result", "Ok", "Err"]
  BUILTIN_CONTAINER_NAMES = ["List", "Map", "Set", "Fiber", "Thread", "VirtualThread", "Channel", "Mutex"]
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
      if @aliases.has_key?(name)
        raise ResolveError.new("Alias '#{name}' already declared", line, col)
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

      if target = @aliases[name]?
        return target
      end

      candidates = @registry.resolve_simple(name)
      case candidates.size
      when 0
        raise ResolveError.new("Unknown type '#{name}'", line, col)
      when 1
        candidates[0]
      else
        in_current = candidates.find { |c| ns_of(c) == current_ns }
        return in_current if in_current
        raise ResolveError.new(
          "Ambiguous type '#{name}' - exists in: #{candidates.join(", ")}. Use a fully-qualified name or alias.",
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
