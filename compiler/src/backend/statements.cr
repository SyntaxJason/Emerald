require "./base"

module Emerald
  class Codegen
    def emit_stmt(io : IO, stmt : AST::Node)
      case stmt
      when AST::VarDecl       then emit_var_decl(io, stmt); io << "\n"
      when AST::AssignStmt    then indent(io); io << stmt.target << " = "; emit_expr(io, stmt.value); io << "\n"
      when AST::ExpressionStmt then indent(io); emit_expr(io, stmt.expression); io << "\n"
      when AST::ReturnStmt    then emit_return(io, stmt)
      when AST::IfStmt        then emit_if(io, stmt)
      when AST::WhileStmt     then emit_while(io, stmt)
      when AST::ForStmt       then emit_for(io, stmt)
      when AST::Block         then emit_block(io, stmt)
      when AST::BreakStmt     then indent(io); io << "break\n"
      when AST::ContinueStmt  then indent(io); io << "next\n"
      else
        raise "Unknown statement: #{stmt.class}"
      end
    end

    private def emit_block(io : IO, block : AST::Block)
      block.statements.each { |s| emit_stmt(io, s) }
    end

    private def emit_var_decl(io : IO, decl : AST::VarDecl)
      indent(io)
      io << decl.name << " = "
      if init = decl.initializer
        emit_expr(io, init)
      else
        io << "nil"
      end
    end

    private def emit_return(io : IO, stmt : AST::ReturnStmt)
      indent(io); io << "return"
      if v = stmt.value
        io << " "
        emit_expr(io, v)
      end
      io << "\n"
    end

    private def emit_if(io : IO, stmt : AST::IfStmt)
      indent(io); io << "if "; emit_expr(io, stmt.condition); io << "\n"
      @indent += 1
      emit_block(io, stmt.then_branch)
      @indent -= 1
      emit_if_tail(io, stmt.else_branch)
    end

    private def emit_if_tail(io : IO, else_branch : AST::Node?)
      case else_branch
      when nil
        indent(io); io << "end\n"
      when AST::Block
        indent(io); io << "else\n"
        @indent += 1
        emit_block(io, else_branch)
        @indent -= 1
        indent(io); io << "end\n"
      when AST::IfStmt
        indent(io); io << "elsif "; emit_expr(io, else_branch.condition); io << "\n"
        @indent += 1
        emit_block(io, else_branch.then_branch)
        @indent -= 1
        emit_if_tail(io, else_branch.else_branch)
      end
    end

    private def emit_while(io : IO, stmt : AST::WhileStmt)
      indent(io); io << "while "; emit_expr(io, stmt.condition); io << "\n"
      @indent += 1
      emit_block(io, stmt.body)
      @indent -= 1
      indent(io); io << "end\n"
    end

    private def emit_for(io : IO, stmt : AST::ForStmt)
      indent(io); io << "("
      emit_expr(io, stmt.iterable)
      io << ").each do |" << stmt.var_name << "|\n"
      @indent += 1
      emit_block(io, stmt.body)
      @indent -= 1
      indent(io); io << "end\n"
    end
  end
end
