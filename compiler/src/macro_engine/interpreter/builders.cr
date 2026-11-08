require "../interpreter"

module Emerald
  module MacroEngine
    class Interpreter
      private def eval_static_builder(fqn : String, args : Array(MacroValue)) : MacroValue
        case fqn
        when "Stmt::expr"
          expr_node = expect_expression_arg(args, 0)
          wrap_ast(AST::ExpressionStmt.new(expr_node), "StatementAST")
        when "Stmt::return"
          ret = AST::ReturnStmt.new(expect_expression_arg(args, 0))
          wrap_ast(ret, "StatementAST")
        when "Stmt::returnVoid"
          wrap_ast(AST::ReturnStmt.new(nil), "StatementAST")
        when "Stmt::var"
          name = expect_string_arg(args, 0)
          type_name = expect_string_arg(args, 1)
          init = expect_expression_arg(args, 2)
          var = AST::VarDecl.new(AST::Mutability::Mutable, AST::NamedType.new(type_name).as(AST::TypeRef), name, init)
          wrap_ast(var, "StatementAST")
        when "Stmt::assign"
          target = expect_string_arg(args, 0)
          assign = AST::AssignStmt.new(target, expect_expression_arg(args, 1))
          wrap_ast(assign, "StatementAST")
        when "Stmt::if"
          cond = expect_expression_arg(args, 0)
          block = expect_block_arg(args, 1)
          if_stmt = AST::IfStmt.new(cond, block)
          wrap_ast(if_stmt, "StatementAST")
        when "Stmt::ifElse"
          cond = expect_expression_arg(args, 0)
          then_block = expect_block_arg(args, 1)
          else_block = expect_block_arg(args, 2)
          if_stmt = AST::IfStmt.new(cond, then_block, else_block)
          wrap_ast(if_stmt, "StatementAST")
        when "Stmt::while"
          cond = expect_expression_arg(args, 0)
          body = expect_block_arg(args, 1)
          while_stmt = AST::WhileStmt.new(cond, body)
          wrap_ast(while_stmt, "StatementAST")

        when "Expr::int"
          wrap_ast(AST::IntLiteral.new(expect_int_arg(args, 0)), "ExpressionAST")
        when "Expr::float"
          wrap_ast(AST::FloatLiteral.new(expect_float_arg(args, 0)), "ExpressionAST")
        when "Expr::str"
          wrap_ast(AST::StringLiteral.new(expect_string_arg(args, 0)), "ExpressionAST")
        when "Expr::bool"
          wrap_ast(AST::BoolLiteral.new(expect_bool_arg(args, 0)), "ExpressionAST")
        when "Expr::ident"
          name = expect_string_arg(args, 0)
          wrap_ast(AST::Identifier.new(name), "ExpressionAST")
        when "Expr::this"
          wrap_ast(AST::ThisExpr.new, "ExpressionAST")
        when "Expr::call"
          callee = expect_string_arg(args, 0)
          arg_list = expect_expr_list_arg(args, 1)
          wrap_ast(AST::CallExpr.new(callee, arg_list), "ExpressionAST")
        when "Expr::methodCall"
          receiver = expect_expression_arg(args, 0)
          name = expect_string_arg(args, 1)
          arg_list = expect_expr_list_arg(args, 2)
          mc = AST::MethodCall.new(receiver, name, arg_list)
          wrap_ast(mc, "ExpressionAST")
        when "Expr::memberAccess"
          receiver = expect_expression_arg(args, 0)
          name = expect_string_arg(args, 1)
          wrap_ast(AST::MemberAccess.new(receiver, name), "ExpressionAST")
        when "Expr::binary"
          op = expect_string_arg(args, 0)
          left = expect_expression_arg(args, 1)
          right = expect_expression_arg(args, 2)
          wrap_ast(AST::BinaryOp.new(op, left, right), "ExpressionAST")

        when "Block::of"
          stmts = expect_stmt_list_arg(args, 0)
          wrap_ast(AST::Block.new(stmts), "BlockAST")
        when "Block::empty"
          wrap_ast(AST::Block.new, "BlockAST")

        when "MethodAST::create"
          name = expect_string_arg(args, 0)
          ret_type = expect_string_arg(args, 1)
          params_list = expect_param_list_arg(args, 2)
          body = expect_block_arg(args, 3)
          md = AST::MethodDecl.new(AST::Visibility::Public, name, params_list, AST::NamedType.new(ret_type), body)
          wrap_ast(md, "MethodAST")

        else
          raise "Macro error: unknown builder '#{fqn}'"
        end
      end


    end
  end
end
