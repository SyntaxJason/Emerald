require "./nodes"
require "./types"
require "./declarations"

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

    class CallExpr < Node
      property callee : String
      property namespace_path : Array(String)
      property args : Array(Node)

      def initialize(@callee, @args)
        @namespace_path = [] of String
      end
    end

    class MemberAccess < Node
      property receiver : Node
      property name : String

      def initialize(@receiver, @name); end
    end

    class MethodCall < Node
      property receiver : Node
      property name : String
      property args : Array(Node)
      property receiver_type : String
      property expected_type : String

      def initialize(@receiver, @name, @args)
        @receiver_type = ""
        @expected_type = ""
      end
    end

    class ThisExpr < Node
    end

    class NewExpr < Node
      property type_name : String
      property namespace_path : Array(String)
      property args : Array(Node)
      property expected_type : String

      def initialize(@type_name, @args)
        @namespace_path = [] of String
        @expected_type = ""
      end

      def fqn : String
        @namespace_path.empty? ? @type_name : "#{@namespace_path.join("::")}::#{@type_name}"
      end
    end

    class MemberAssign < Node
      property receiver : Node
      property name : String
      property value : Node

      def initialize(@receiver, @name, @value); end
    end

    class RangeExpr < Node
      property start : Node
      property finish : Node
      property inclusive : Bool

      def initialize(@start, @finish, @inclusive = true); end
    end

    class LambdaExpr < Node
      property params : Array(Param)
      property return_type : TypeRef?
      property body : Node
      property is_expression_body : Bool

      def initialize(@params, @return_type, @body, @is_expression_body); end
    end

    class MethodRef < Node
      property receiver : Node?
      property type_name : String?
      property method_name : String

      def initialize(@receiver, @type_name, @method_name); end
    end

    class OkExpr < Node
      property value : Node

      def initialize(@value); end
    end

    class ErrExpr < Node
      property value : Node

      def initialize(@value); end
    end
  end
end
