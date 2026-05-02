require "./nodes"

module Emerald
  module AST
    class Block < Node
      property statements : Array(Node)

      def initialize(@statements = [] of Node); end
    end

    class ExpressionStmt < Node
      property expression : Node

      def initialize(@expression); end
    end

    class ReturnStmt < Node
      property value : Node?

      def initialize(@value = nil); end
    end

    class IfStmt < Node
      property condition : Node
      property then_branch : Block
      property else_branch : Node?

      def initialize(@condition, @then_branch, @else_branch = nil); end
    end

    class WhileStmt < Node
      property condition : Node
      property body : Block

      def initialize(@condition, @body); end
    end

    class ForStmt < Node
      property var_name : String
      property iterable : Node
      property body : Block

      def initialize(@var_name, @iterable, @body); end
    end

    class BreakStmt < Node
    end

    class ContinueStmt < Node
    end

    class AssignStmt < Node
      property target : String
      property value : Node

      def initialize(@target, @value); end
    end
  end
end
