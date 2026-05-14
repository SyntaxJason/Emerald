require "../expressions"

module Emerald
  module AST
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

    class MethodRef < Node
      property receiver : Node?
      property type_name : String?
      property method_name : String

      def initialize(@receiver, @type_name, @method_name); end
    end

  end
end
