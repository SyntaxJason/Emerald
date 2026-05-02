require "../frontend/ast"

module Emerald
  class ResolveError < Exception
    getter line : Int32
    getter col : Int32

    def initialize(message : String, @line, @col)
      super("#{message} at #{@line}:#{@col}")
    end
  end

  abstract class Symbol
    getter name : String

    def initialize(@name); end
  end

  class VarSymbol < Symbol
    getter mutability : AST::Mutability
    property type_name : String

    def initialize(name : String, @mutability, @type_name = "?")
      super(name)
    end
  end

  class FunctionSymbol < Symbol
    getter param_types : Array(String)
    getter return_type : String
    getter fqn : String

    def initialize(name : String, @param_types, @return_type, @fqn = "")
      super(name)
      @fqn = name if @fqn.empty?
    end
  end

  class TypeSymbol < Symbol
    getter kind : String
    getter fqn : String

    def initialize(name : String, @kind, @fqn = "")
      super(name)
      @fqn = name if @fqn.empty?
    end
  end

  class AliasSymbol < Symbol
    getter target_fqn : String

    def initialize(name : String, @target_fqn)
      super(name)
    end
  end

  class Scope
    getter parent : Scope?
    getter symbols : Hash(String, Symbol)

    def initialize(@parent = nil)
      @symbols = {} of String => Symbol
    end

    def declare(name : String, sym : Symbol, line : Int32, col : Int32)
      if @symbols.has_key?(name)
        raise ResolveError.new("Symbol '#{name}' already declared in this scope", line, col)
      end
      @symbols[name] = sym
    end

    def lookup(name : String) : Symbol?
      @symbols[name]? || @parent.try(&.lookup(name))
    end
  end
end
