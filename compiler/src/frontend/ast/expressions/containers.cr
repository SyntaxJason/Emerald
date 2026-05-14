require "../expressions"

module Emerald
  module AST
    class LambdaExpr < Node
      property params : Array(Param)
      property return_type : TypeRef?
      property body : Node
      property is_expression_body : Bool
      property expected_type : String
      property sam_adapter_name : String

      def initialize(@params, @return_type, @body, @is_expression_body)
        @expected_type = ""
        @sam_adapter_name = ""
      end
    end

    class OkExpr < Node
      property value : Node

      def initialize(@value); end
    end

    class ErrExpr < Node
      property value : Node

      def initialize(@value); end
    end

    class ListLiteral < Node
      property elements : Array(Node)

      def initialize(@elements); end
    end

    class IndexExpr < Node
      property receiver : Node
      property index : Node

      def initialize(@receiver, @index); end
    end

  end
end
