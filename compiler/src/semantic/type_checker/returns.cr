require "../type_checker"

module Emerald
  class TypeChecker
    private def ensure_explicit_return(block : AST::Block, expected : String, label : String, line : Int32, col : Int32)
      return if expected == "Void"
      return if block_guarantees_return?(block)

      raise TypeError.new(
        "#{label} must return #{expected}",
        line,
        col,
        "Add an explicit return statement or change the return type to Void")
    end

    private def block_guarantees_return?(block : AST::Block) : Bool
      block.statements.any? { |stmt| stmt_guarantees_return?(stmt) }
    end

    private def stmt_guarantees_return?(stmt : AST::Node) : Bool
      case stmt
      when AST::ReturnStmt
        true
      when AST::Block
        block_guarantees_return?(stmt)
      when AST::IfStmt
        return false unless stmt.else_branch

        then_returns = block_guarantees_return?(stmt.then_branch)
        else_returns = case else_branch = stmt.else_branch
                       when AST::Block
                         block_guarantees_return?(else_branch)
                       when AST::IfStmt
                         stmt_guarantees_return?(else_branch)
                       else
                         false
                       end

        then_returns && else_returns
      else
        false
      end
    end

  end
end
