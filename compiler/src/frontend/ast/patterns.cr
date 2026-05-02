require "./nodes"

module Emerald
  module AST
    abstract class Pattern < Node
    end

    class WildcardPattern < Pattern
    end

    class LiteralPattern < Pattern
      property value : Node

      def initialize(@value); end
    end

    class RangePattern < Pattern
      property start : Node
      property finish : Node
      property inclusive : Bool

      def initialize(@start, @finish, @inclusive = true); end
    end

    class TypePattern < Pattern
      property type_name : String
      property binding : String?

      def initialize(@type_name, @binding); end
    end

    class NullPattern < Pattern
    end

    class DestructurePattern < Pattern
      property type_name : String
      property sub_patterns : Array(Pattern)

      def initialize(@type_name, @sub_patterns); end
    end

    class BindPattern < Pattern
      property name : String

      def initialize(@name); end
    end

    class MatchArm < Node
      property patterns : Array(Pattern)
      property guard : Node?
      property body : Node

      def initialize(@patterns, @guard, @body); end
    end

    class MatchExpr < Node
      property subject : Node
      property arms : Array(MatchArm)
      property subject_type : String

      def initialize(@subject, @arms)
        @subject_type = "?"
      end
    end
  end
end
