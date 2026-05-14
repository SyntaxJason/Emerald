require "../expressions"

module Emerald
  class Codegen
    private def emit_interp(io : IO, expr : AST::StringInterp)
      io << '"'
      expr.parts.each do |part|
        case part
        when AST::InterpText
          io << escape_for_dq(part.value)
        when AST::InterpExpr
          io << '#' << '{'
          emit_expr(io, part.expression)
          io << '}'
        end
      end
      io << '"'
    end

    private def emit_lambda(io : IO, expr : AST::LambdaExpr)
      unless expr.sam_adapter_name.empty?
        io << expr.sam_adapter_name << ".new("
        emit_proc_lambda(io, expr)
        io << ")"
        return
      end

      emit_proc_lambda(io, expr)
    end

    private def emit_proc_lambda(io : IO, expr : AST::LambdaExpr)
      io << "->("
      expr.params.each_with_index do |p, i|
        io << ", " if i > 0
        io << p.name << " : " << crystal_type(type_ref_name(p.type_ref))
      end
      io << ") {\n"
      @indent += 1
      body = expr.body
      if body.is_a?(AST::Block)
        body.as(AST::Block).statements.each { |s| emit_stmt(io, s) }
      else
        indent(io)
        emit_expr(io, body)
        io << "\n"
      end
      @indent -= 1
      indent(io); io << "}"
    end

    private def emit_method_ref(io : IO, expr : AST::MethodRef)
      if tn = expr.type_name
        candidates = @resolver.registry.resolve_simple(tn)
        type_fqn = candidates.empty? ? tn : candidates.first
        io << "->(__r : " << mangle_fqn(type_fqn) << ") { __r." << expr.method_name << " }"
      elsif recv = expr.receiver
        io << "->{ "
        emit_expr(io, recv)
        io << "." << expr.method_name << " }"
      end
    end

    private def prepare_sam_lambdas(node : AST::Node)
      case node
      when AST::Program
        node.declarations.each { |decl| prepare_sam_lambdas(decl) }
      when AST::Block
        node.statements.each { |stmt| prepare_sam_lambdas(stmt) }
      when AST::FunctionDecl
        prepare_sam_lambdas(node.body)
      when AST::MainDecl
        prepare_sam_lambdas(node.body)
      when AST::ClassDecl
        node.fields.each do |field|
          if init = field.initializer
            prepare_sam_lambdas(init)
          end
        end
        node.constructors.each { |ctor| prepare_sam_lambdas(ctor.body) }
        node.methods.each do |method|
          if body = method.body
            prepare_sam_lambdas(body)
          end
        end
      when AST::InterfaceDecl
        node.methods.each do |method|
          if body = method.body
            prepare_sam_lambdas(body)
          end
        end
      when AST::VarDecl
        if init = node.initializer
          prepare_sam_lambdas(init)
        end
      when AST::AssignStmt
        prepare_sam_lambdas(node.value)
      when AST::ExpressionStmt
        prepare_sam_lambdas(node.expression)
      when AST::ReturnStmt
        if value = node.value
          prepare_sam_lambdas(value)
        end
      when AST::IfStmt
        prepare_sam_lambdas(node.condition)
        prepare_sam_lambdas(node.then_branch)
        if branch = node.else_branch
          prepare_sam_lambdas(branch)
        end
      when AST::WhileStmt
        prepare_sam_lambdas(node.condition)
        prepare_sam_lambdas(node.body)
      when AST::ForStmt
        prepare_sam_lambdas(node.iterable)
        prepare_sam_lambdas(node.body)
      when AST::BinaryOp
        prepare_sam_lambdas(node.left)
        prepare_sam_lambdas(node.right)
      when AST::UnaryOp
        prepare_sam_lambdas(node.operand)
      when AST::CallExpr
        node.args.each { |arg| prepare_sam_lambdas(arg) }
      when AST::NewExpr
        node.args.each { |arg| prepare_sam_lambdas(arg) }
      when AST::MethodCall
        prepare_sam_lambdas(node.receiver)
        node.args.each { |arg| prepare_sam_lambdas(arg) }
      when AST::MemberAccess
        prepare_sam_lambdas(node.receiver)
      when AST::MemberAssign
        prepare_sam_lambdas(node.receiver)
        prepare_sam_lambdas(node.value)
      when AST::RangeExpr
        prepare_sam_lambdas(node.start)
        prepare_sam_lambdas(node.finish)
      when AST::StringInterp
        node.parts.each do |part|
          if part.is_a?(AST::InterpExpr)
            prepare_sam_lambdas(part.as(AST::InterpExpr).expression)
          end
        end
      when AST::LambdaExpr
        prepare_sam_lambda(node)
        prepare_sam_lambdas(node.body)
      when AST::OkExpr
        prepare_sam_lambdas(node.value)
      when AST::ErrExpr
        prepare_sam_lambdas(node.value)
      when AST::ListLiteral
        node.elements.each { |element| prepare_sam_lambdas(element) }
      when AST::IndexExpr
        prepare_sam_lambdas(node.receiver)
        prepare_sam_lambdas(node.index)
      when AST::MatchExpr
        prepare_sam_lambdas(node.subject)
        node.arms.each do |arm|
          if guard = arm.guard
            prepare_sam_lambdas(guard)
          end
          prepare_sam_lambdas(arm.body)
        end
      end
    end

    private def prepare_sam_lambda(expr : AST::LambdaExpr)
      return if expr.expected_type.empty?
      return unless sam_signature_for_type(expr.expected_type)
      return unless expr.sam_adapter_name.empty?

      @sam_lambda_counter += 1
      expr.sam_adapter_name = "EmeraldSamLambda#{@sam_lambda_counter}"
      @sam_lambda_adapters << expr
    end

    private def emit_sam_lambda_adapters(io : IO)
      @sam_lambda_adapters.each do |expr|
        signature = sam_signature_for_type(expr.expected_type)
        next unless signature

        method_name = signature[0]
        param_types = signature[1]
        return_type = signature[2]
        adapter_name = expr.sam_adapter_name

        io << "class " << adapter_name << "\n"
        @indent += 1
        indent(io); io << "include " << mangle_fqn(base_type_name(expr.expected_type)) << "\n"
        indent(io); io << "def initialize(@__fn : " << proc_type(param_types, return_type) << ")\n"
        indent(io); io << "end\n\n"
        indent(io); io << "def " << method_name << "("
        param_types.each_with_index do |param_type, index|
          io << ", " if index > 0
          io << "__p" << index << " : " << crystal_type(param_type)
        end
        io << ") : " << crystal_type(return_type) << "\n"
        @indent += 1
        indent(io); io << "@__fn.call("
        param_types.each_with_index do |_param_type, index|
          io << ", " if index > 0
          io << "__p" << index
        end
        io << ")\n"
        @indent -= 1
        indent(io); io << "end\n"
        @indent -= 1
        io << "end\n\n"
      end
    end

    private def proc_type(param_types : Array(String), return_type : String) : String
      crystal_params = param_types.map { |param_type| crystal_type(param_type) }
      crystal_return = crystal_type(return_type)
      return "Proc(#{crystal_return})" if crystal_params.empty?

      "Proc(#{crystal_params.join(", ")}, #{crystal_return})"
    end

    private def sam_signature_for_type(type_name : String) : Tuple(String, Array(String), String)?
      methods = abstract_methods_with_subs(type_name)
      return nil unless methods.size == 1

      method = methods[0][0]
      subs = methods[0][1]
      params = method.param_types.map { |param| apply_type_subs(param, subs) }
      {method.name, params, apply_type_subs(method.return_type, subs)}
    end

    private def abstract_methods_with_subs(type_name : String) : Array(Tuple(MethodInfo, Hash(String, String)))
      base, subs = base_type_and_subs_for_codegen(type_name)
      info = @resolver.registry[base]
      return [] of Tuple(MethodInfo, Hash(String, String)) unless info
      return [] of Tuple(MethodInfo, Hash(String, String)) unless info.is_interface

      result = [] of Tuple(MethodInfo, Hash(String, String))

      info.interfaces.each do |iface|
        parent_type = apply_type_subs(iface, subs)
        abstract_methods_with_subs(parent_type).each do |entry|
          result << entry unless result.any? { |existing| existing[0].name == entry[0].name }
        end
      end

      info.methods.each_value do |method|
        next unless method.is_abstract

        result.reject! { |entry| entry[0].name == method.name }
        result << {method, subs}
      end

      result
    end

    private def base_type_and_subs_for_codegen(type_name : String) : Tuple(String, Hash(String, String))
      subs = {} of String => String
      return {type_name, subs} unless type_name.includes?("<") && type_name.ends_with?(">")

      open = type_name.index("<").not_nil!
      base = type_name[0...open]
      args = split_top_level_args(type_name[(open + 1)..-2])
      info = @resolver.registry[base]
      return {base, subs} unless info

      info.type_params.each_with_index do |param, index|
        subs[param] = args[index]? || "?"
      end

      {base, subs}
    end

    private def apply_type_subs(type_name : String, subs : Hash(String, String)) : String
      result = type_name
      subs.each do |param, replacement|
        result = substitute_type_param(result, param, replacement)
      end
      result
    end

    private def substitute_type_param(type_name : String, param : String, replacement : String) : String
      result = ""
      index = 0
      while index < type_name.size
        if index + param.size <= type_name.size && type_name[index, param.size] == param
          before_ok = index == 0 || !identifier_char?(type_name[index - 1])
          after_ok = index + param.size == type_name.size || !identifier_char?(type_name[index + param.size])
          if before_ok && after_ok
            result += replacement
            index += param.size
            next
          end
        end
        result += type_name[index].to_s
        index += 1
      end
      result
    end

    private def identifier_char?(char : Char) : Bool
      char.ascii_alphanumeric? || char == '_'
    end

  end
end
