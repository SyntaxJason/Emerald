module Emerald
  module AST
    abstract class Node
      property line : Int32 = 0
      property col : Int32 = 0

      def at(line : Int32, col : Int32) : self
        @line = line
        @col = col
        self
      end
    end

    class QualifiedName < Node
      property segments : Array(String)

      def initialize(@segments); end

      def to_s : String
        @segments.join("::")
      end
    end

    class Program < Node
      property declarations : Array(Node)
      property namespace_decl : QualifiedName?
      property source_path : String?

      def initialize
        @declarations = [] of Node
        @namespace_decl = nil
        @source_path = nil
      end
    end

    enum Visibility
      Public
      Private
      Protected
      Internal
    end

    enum Mutability
      Mutable
      Final
      Cryo
    end
  end
end
