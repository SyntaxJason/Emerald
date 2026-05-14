require "../expressions"

module Emerald
  module AST
    class Identifier < Node
      property name : String
      property namespace_path : Array(String)

      def initialize(@name)
        @namespace_path = [] of String
      end

      def fqn : String
        @namespace_path.empty? ? @name : "#{@namespace_path.join("::")}::#{@name}"
      end
    end

    class ThisExpr < Node
    end

  end
end
