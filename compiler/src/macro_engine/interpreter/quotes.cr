require "../interpreter"
require "../quote_unquote_expander"

module Emerald
  module MacroEngine
    class Interpreter
      private def eval_quote_expr(expr : AST::QuoteExpr) : MacroValue
        quoted = QuoteUnquoteExpander.new(self).expand(expr.quoted)

        case expr.kind
        when "expr"
          MacroASTRef.new(quoted, "ExpressionAST")
        when "stmt"
          MacroASTRef.new(quoted, "StatementAST")
        when "block"
          MacroASTRef.new(quoted, "BlockAST")
        when "method"
          MacroASTRef.new(quoted, "MethodAST")
        when "field"
          MacroASTRef.new(quoted, "FieldAST")
        else
          raise "Macro error: unknown quote kind '#{expr.kind}'"
        end
      end

    end
  end
end
