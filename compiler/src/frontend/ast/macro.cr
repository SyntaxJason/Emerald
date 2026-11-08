require "./nodes"
require "./statements"

module Emerald
  module AST
    class MacroDecl < Node
      property name : String
      property target : String  # "Method" or "Class"
      property body : Block
      property namespace : String

      def initialize(@name, @target, @body)
        @namespace = ""
      end
    end

    class MacroRegistry
      property macros : Hash(String, MacroDecl)

    end

    class Annotation < Node
      property name : String
      property args : Array(Node)

      def initialize(@name, @args); end
    end

    class MacroRegistry
      property macros : Hash(String, MacroDecl)

      def initialize
        @macros = {} of String => MacroDecl
      end

      def register(macro_decl : MacroDecl)
        @macros[macro_decl.name] = macro_decl
      end

      def find(name : String) : MacroDecl?
        @macros[name]?
      end
    end
  end
end
