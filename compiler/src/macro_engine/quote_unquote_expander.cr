require "./interpreter"

module Emerald
  module MacroEngine
    class QuoteUnquoteExpander
      def initialize(@interpreter : Interpreter)
      end

      def expand(node : AST::Node) : AST::Node
        case node
        when AST::UnquoteExpr
          value = @interpreter.eval_expr(node.expression)

          unless value.is_a?(MacroASTRef)
            raise "Macro error: unquote expected AST value, got #{value.class}"
          end

          value.node

        when AST::Block
          AST::Block.new(node.statements.map { |stmt| expand(stmt) }).at(node.line, node.col)

        when AST::MethodDecl
          body = node.body ? expand(node.body.not_nil!).as(AST::Block) : nil

          copy = AST::MethodDecl.new(
            node.visibility,
            node.name,
            node.params,
            node.return_type,
            body,
            node.is_override,
            node.is_default,
            node.is_abstract
          ).at(node.line, node.col).as(AST::MethodDecl)

          copy.is_synchronized = node.is_synchronized
          copy.is_async = node.is_async
          copy.deprecated_message = node.deprecated_message
          copy.annotations = node.annotations.dup
          copy

        when AST::FieldDecl
          initializer = node.initializer ? expand(node.initializer.not_nil!) : nil

          AST::FieldDecl.new(
            node.visibility,
            node.mutability,
            node.type_ref,
            node.name,
            initializer
          ).at(node.line, node.col)

        when AST::ExpressionStmt
          AST::ExpressionStmt.new(expand(node.expression)).at(node.line, node.col)

        when AST::ReturnStmt
          value = node.value ? expand(node.value.not_nil!) : nil
          AST::ReturnStmt.new(value).at(node.line, node.col)

        when AST::IfStmt
          else_branch = node.else_branch ? expand(node.else_branch.not_nil!) : nil
          AST::IfStmt.new(
            expand(node.condition),
            expand(node.then_branch).as(AST::Block),
            else_branch
          ).at(node.line, node.col)

        when AST::WhileStmt
          AST::WhileStmt.new(
            expand(node.condition),
            expand(node.body).as(AST::Block)
          ).at(node.line, node.col)

        when AST::ForStmt
          AST::ForStmt.new(
            node.var_name,
            expand(node.iterable),
            expand(node.body).as(AST::Block)
          ).at(node.line, node.col)

        when AST::AssignStmt
          AST::AssignStmt.new(node.target, expand(node.value)).at(node.line, node.col)

        when AST::VarDecl
          initializer = node.initializer ? expand(node.initializer.not_nil!) : nil
          AST::VarDecl.new(node.mutability, node.type_ref, node.name, initializer).at(node.line, node.col)

        when AST::BinaryOp
          copy = AST::BinaryOp.new(
            node.op,
            expand(node.left),
            expand(node.right)
          ).at(node.line, node.col)
          copy.result_type = node.result_type
          copy

        when AST::UnaryOp
          AST::UnaryOp.new(node.op, expand(node.operand)).at(node.line, node.col)

        when AST::CallExpr
          copy = AST::CallExpr.new(
            node.callee,
            node.args.map { |arg| expand(arg) }
          ).at(node.line, node.col)
          copy.namespace_path = node.namespace_path.dup
          copy

        when AST::MethodCall
          copy = AST::MethodCall.new(
            expand(node.receiver),
            node.name,
            node.args.map { |arg| expand(arg) }
          ).at(node.line, node.col)
          copy.receiver_type = node.receiver_type
          copy.expected_type = node.expected_type
          copy

        when AST::MemberAccess
          AST::MemberAccess.new(expand(node.receiver), node.name).at(node.line, node.col)

        when AST::MemberAssign
          AST::MemberAssign.new(
            expand(node.receiver),
            node.name,
            expand(node.value)
          ).at(node.line, node.col)

        when AST::NewExpr
          copy = AST::NewExpr.new(
            node.type_name,
            node.args.map { |arg| expand(arg) }
          ).at(node.line, node.col)
          copy.namespace_path = node.namespace_path.dup
          copy.expected_type = node.expected_type
          copy

        when AST::RangeExpr
          AST::RangeExpr.new(
            expand(node.start),
            expand(node.finish),
            node.inclusive
          ).at(node.line, node.col)

        when AST::LambdaExpr
          AST::LambdaExpr.new(
            node.params,
            node.return_type,
            expand(node.body),
            node.is_expression_body
          ).at(node.line, node.col)

        when AST::OkExpr
          AST::OkExpr.new(expand(node.value)).at(node.line, node.col)

        when AST::ErrExpr
          AST::ErrExpr.new(expand(node.value)).at(node.line, node.col)

        when AST::ListLiteral
          AST::ListLiteral.new(node.elements.map { |element| expand(element) }).at(node.line, node.col)

        when AST::IndexExpr
          AST::IndexExpr.new(
            expand(node.receiver),
            expand(node.index)
          ).at(node.line, node.col)

        when AST::StringInterp
          parts = [] of AST::InterpSegment

          node.parts.each do |part|
            case part
            when AST::InterpText
              parts << AST::InterpText.new(part.value)
            when AST::InterpExpr
              parts << AST::InterpExpr.new(expand(part.expression))
            end
          end

          AST::StringInterp.new(parts).at(node.line, node.col)

        else
          node
        end
      end


    end
  end
end
