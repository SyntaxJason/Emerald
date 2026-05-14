require "../expressions"

module Emerald
  module AST
    class BinaryOp < Node
      property op : String
      property left : Node
      property right : Node
      property result_type : String

      def initialize(@op, @left, @right)
        @result_type = "?"
      end
    end

    class UnaryOp < Node
      property op : String
      property operand : Node

      def initialize(@op, @operand); end
    end

    class RangeExpr < Node
      property start : Node
      property finish : Node
      property inclusive : Bool

      def initialize(@start, @finish, @inclusive = true); end
    end

  end
end
