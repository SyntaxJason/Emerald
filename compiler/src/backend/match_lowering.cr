require "./base"
require "../semantic/type_system"

module Emerald
  class Codegen
    def emit_match(io : IO, expr : AST::MatchExpr)
      subj_var = fresh_match_var
      subj_type = expr.subject_type
      io << "begin\n"
      @indent += 1
      indent(io); io << subj_var << " = "
      emit_expr(io, expr.subject)
      io << "\n"
      indent(io); io << "loop do\n"
      @indent += 1
      expr.arms.each do |arm|
        emit_match_arm(io, arm, subj_var, subj_type)
      end
      indent(io); io << "raise \"Match error - no arm matched\"\n"
      @indent -= 1
      indent(io); io << "end\n"
      @indent -= 1
      indent(io); io << "end"
    end

    private def emit_match_arm(io : IO, arm : AST::MatchArm, subj_var : String, subj_type : String)
      tests = arm.patterns.map do |p|
        String.build { |sb| emit_pattern_test(sb, p, subj_var) }
      end
      indent(io); io << "if (" << tests.join(") || (") << ")\n"
      @indent += 1
      emit_pattern_bindings(io, arm.patterns.first, subj_var, subj_type)
      if g = arm.guard
        indent(io); io << "if "
        emit_expr(io, g)
        io << "\n"
        @indent += 1
        emit_arm_body(io, arm)
        @indent -= 1
        indent(io); io << "end\n"
      else
        emit_arm_body(io, arm)
      end
      @indent -= 1
      indent(io); io << "end\n"
    end

    private def emit_arm_body(io : IO, arm : AST::MatchArm)
      body = arm.body
      if body.is_a?(AST::Block)
        body.as(AST::Block).statements.each { |s| emit_stmt(io, s) }
        indent(io); io << "break\n"
      else
        indent(io); io << "break "
        emit_expr(io, body)
        io << "\n"
      end
    end

    private def emit_pattern_test(io : IO, pat : AST::Pattern, subj_var : String)
      case pat
      when AST::WildcardPattern, AST::BindPattern
        io << "true"
      when AST::NullPattern
        io << subj_var << ".nil?"
      when AST::LiteralPattern
        io << subj_var << " == "
        emit_expr(io, pat.value)
      when AST::RangePattern
        io << "(("
        emit_expr(io, pat.start)
        io << ").."
        emit_expr(io, pat.finish)
        io << ").includes?(" << subj_var << ")"
      when AST::TypePattern
        crystal_t = crystal_type(pat.type_name)
        io << subj_var << ".is_a?(" << crystal_t << ")"
      when AST::DestructurePattern
        case pat.type_name
        when "Ok"
          io << "(" << subj_var << ".is_a?(EmeraldResult) && " << subj_var << ".as(EmeraldResult).is_ok?)"
        when "Err"
          io << "(" << subj_var << ".is_a?(EmeraldResult) && " << subj_var << ".as(EmeraldResult).is_err?)"
        else
          candidates = @resolver.registry.resolve_simple(pat.type_name)
          fqn = candidates.empty? ? pat.type_name : candidates.first
          io << subj_var << ".is_a?(" << mangle_fqn(fqn) << ")"
        end
      end
    end

    def emit_pattern_bindings(io : IO, pat : AST::Pattern, subj_var : String, subj_type : String = "?")
      case pat
      when AST::TypePattern
        if b = pat.binding
          ct = crystal_type(pat.type_name)
          indent(io); io << b << " = " << subj_var << ".as(" << ct << ")\n"
        end
      when AST::BindPattern
        indent(io); io << pat.name << " = " << subj_var << "\n"
      when AST::DestructurePattern
        case pat.type_name
        when "Ok"
          unless pat.sub_patterns.empty?
            sub = pat.sub_patterns[0]
            sub_var = "__inner"
            inner_type = TypeSystem.result_inner_ok_type(subj_type)
            ct = crystal_type(inner_type)
            indent(io); io << sub_var << " = " << subj_var << ".as(EmeraldResult).raw_value.as(EmeraldBox(" << ct << ")).value\n"
            emit_pattern_bindings_with_var(io, sub, sub_var, inner_type)
          end
        when "Err"
          unless pat.sub_patterns.empty?
            sub = pat.sub_patterns[0]
            sub_var = "__inner"
            inner_type = TypeSystem.result_inner_err_type(subj_type)
            ct = crystal_type(inner_type)
            indent(io); io << sub_var << " = " << subj_var << ".as(EmeraldResult).raw_value.as(EmeraldBox(" << ct << ")).value\n"
            emit_pattern_bindings_with_var(io, sub, sub_var, inner_type)
          end
        else
          candidates = @resolver.registry.resolve_simple(pat.type_name)
          fqn = candidates.empty? ? pat.type_name : candidates.first
          info = @registry[fqn]
          if info
            fields = info.fields.values.to_a
            pat.sub_patterns.each_with_index do |sub, i|
              sub_var = "__f#{i}"
              indent(io); io << sub_var << " = " << subj_var << ".as(" << mangle_fqn(fqn) << ")." << fields[i].name << "\n"
              emit_pattern_bindings_with_var(io, sub, sub_var, fields[i].type_name)
            end
          end
        end
      end
    end

    private def emit_pattern_bindings_with_var(io : IO, pat : AST::Pattern, var : String, type : String = "?")
      case pat
      when AST::BindPattern
        indent(io); io << pat.name << " = " << var << "\n"
      when AST::TypePattern
        if b = pat.binding
          ct = crystal_type(pat.type_name)
          indent(io); io << b << " = " << var << ".as(" << ct << ")\n"
        end
      when AST::DestructurePattern
        emit_pattern_bindings(io, pat, var, type)
      end
    end
  end
end
