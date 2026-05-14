require "../expressions"

module Emerald
  module AST
    class QuoteExpr < Node
      property kind : String
      property quoted : Node

      def initialize(@kind, @quoted); end
    end

    class UnquoteExpr < Node
      property expression : Node

      def initialize(@expression); end
    end

  end
end
