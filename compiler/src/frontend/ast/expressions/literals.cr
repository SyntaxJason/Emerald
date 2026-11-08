require "../expressions"

module Emerald
  module AST
    class IntLiteral < Node
      property value : Int64

      def initialize(@value); end
    end

    class FloatLiteral < Node
      property value : Float64

      def initialize(@value); end
    end

    class StringLiteral < Node
      property value : String

      def initialize(@value); end
    end

    abstract class InterpSegment
    end

    class InterpText < InterpSegment
      property value : String

      def initialize(@value); end
    end

    class InterpExpr < InterpSegment
      property expression : Node

      def initialize(@expression); end
    end

    class StringInterp < Node
      property parts : Array(InterpSegment)

      def initialize(@parts); end
    end

    class CharLiteral < Node
      property value : String

      def initialize(@value); end
    end

    class BoolLiteral < Node
      property value : Bool

      def initialize(@value); end
    end

  end
end
