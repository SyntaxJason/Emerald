require "../frontend/ast"
require "./resolver"
require "./type_system"
require "./builtin_methods"

module Emerald
  class TypeError < Exception
    getter line : Int32
    getter col : Int32

    def initialize(message : String, @line, @col)
      super("#{message} at #{@line}:#{@col}")
    end
  end

  class TypeChecker
    @current_function_return : String?
    @current_class : String?
    @lambda_first_return_type : String?
    @current_namespace : String
    @current_type_params : Array(String)

    def initialize(@resolver : Resolver)
      @current_function_return = nil
      @current_class = nil
      @lambda_first_return_type = nil
      @current_namespace = ""
      @current_type_params = [] of String
    end

    def check(program : AST::Program)
      ns = if decl = program.namespace_decl
             decl.to_s
           else
             DEFAULT_ROOT_NAMESPACE
           end
      @current_namespace = ns
      program.declarations.each { |d| check_declaration(d) }
    end

    private def check_declaration(decl : AST::Node)
      case decl
      when AST::FunctionDecl
        check_function(decl)
      when AST::MainDecl
        check_main(decl)
      when AST::VarDecl
        check_var_decl(decl, @resolver.global_scope)
      when AST::ClassDecl
        check_class(decl)
      when AST::InterfaceDecl
        check_interface(decl)
      when AST::AliasDecl
      when AST::ExpressionStmt, AST::IfStmt, AST::WhileStmt, AST::ForStmt,
           AST::AssignStmt, AST::ReturnStmt, AST::Block,
           AST::BreakStmt, AST::ContinueStmt
        check_stmt(decl, @resolver.global_scope)
      end
    end

    private def check_function(fn : AST::FunctionDecl)
      ret = type_ref_to_fqn(fn.return_type)
      fn_scope = Scope.new(@resolver.global_scope)
      fn.params.each do |p|
        fn_scope.declare(p.name,
          VarSymbol.new(p.name, AST::Mutability::Mutable, type_ref_to_fqn(p.type_ref)),
          p.line, p.col)
      end
      saved = @current_function_return
      @current_function_return = ret
      check_block(fn.body, fn_scope)
      @current_function_return = saved
    end

    private def check_main(main : AST::MainDecl)
      saved = @current_function_return
      @current_function_return = "Void"
      main_scope = Scope.new(@resolver.global_scope)
      check_block(main.body, main_scope)
      @current_function_return = saved
    end

    private def check_class(decl : AST::ClassDecl)
      saved = @current_class
      saved_tp = @current_type_params
      @current_type_params = decl.type_params
      this_type = if decl.type_params.empty?
                    "#{decl.namespace}::#{decl.name}"
                  else
                    "#{decl.namespace}::#{decl.name}<#{decl.type_params.join(",")}>"
                  end
      @current_class = this_type

      decl.fields.each do |f|
        if init = f.initializer
          init_type = check_expr(init, @resolver.global_scope)
          declared = type_ref_to_fqn(f.type_ref)
          unless types_compatible?(declared, init_type)
            raise TypeError.new("Field '#{f.name}': expected #{declared}, got #{init_type}", f.line, f.col)
          end
        end
      end

      decl.constructors.each do |ctor|
        ctor_scope = Scope.new(@resolver.global_scope)
        ctor_scope.declare("this",
          VarSymbol.new("this", AST::Mutability::Final, this_type),
          ctor.line, ctor.col)
        ctor.params.each do |p|
          ctor_scope.declare(p.name,
            VarSymbol.new(p.name, AST::Mutability::Mutable, type_ref_to_fqn(p.type_ref)),
            p.line, p.col)
        end
        saved_ret = @current_function_return
        @current_function_return = "Void"
        check_block(ctor.body, ctor_scope)
        @current_function_return = saved_ret
      end

      decl.methods.each do |m|
        next if m.is_abstract
        body = m.body
        next if body.nil?

        m_scope = Scope.new(@resolver.global_scope)
        m_scope.declare("this",
          VarSymbol.new("this", AST::Mutability::Final, this_type),
          m.line, m.col)
        m.params.each do |p|
          m_scope.declare(p.name,
            VarSymbol.new(p.name, AST::Mutability::Mutable, type_ref_to_fqn(p.type_ref)),
            p.line, p.col)
        end
        saved_ret = @current_function_return
        @current_function_return = type_ref_to_fqn(m.return_type)
        check_block(body, m_scope)
        @current_function_return = saved_ret
      end

      @current_type_params = saved_tp
      @current_class = saved
    end

    private def check_interface(decl : AST::InterfaceDecl)
      decl.methods.each do |m|
        next unless m.is_default
        body = m.body
        next if body.nil?
        saved = @current_class
        @current_class = "#{decl.namespace}::#{decl.name}"
        m_scope = Scope.new(@resolver.global_scope)
        m_scope.declare("this",
          VarSymbol.new("this", AST::Mutability::Final, "#{decl.namespace}::#{decl.name}"),
          m.line, m.col)
        m.params.each do |p|
          m_scope.declare(p.name,
            VarSymbol.new(p.name, AST::Mutability::Mutable, type_ref_to_fqn(p.type_ref)),
            p.line, p.col)
        end
        saved_ret = @current_function_return
        @current_function_return = type_ref_to_fqn(m.return_type)
        check_block(body, m_scope)
        @current_function_return = saved_ret
        @current_class = saved
      end
    end

    private def check_block(block : AST::Block, parent : Scope)
      scope = Scope.new(parent)
      block.statements.each { |s| check_stmt(s, scope) }
    end

    private def check_stmt(stmt : AST::Node, scope : Scope)
      case stmt
      when AST::VarDecl
        check_var_decl(stmt, scope)
      when AST::AssignStmt
        sym = scope.lookup(stmt.target).as(VarSymbol)
        value_type = check_expr(stmt.value, scope)
        unless types_compatible?(sym.type_name, value_type)
          raise TypeError.new("Cannot assign #{value_type} to '#{stmt.target}' of type #{sym.type_name}",
            stmt.line, stmt.col)
        end
      when AST::ExpressionStmt
        check_expr(stmt.expression, scope)
      when AST::ReturnStmt
        expected = @current_function_return || "Void"
        if v = stmt.value
          actual = check_expr(v, scope)
          if expected == "Any"
            @lambda_first_return_type ||= actual
          else
            unless types_compatible?(expected, actual)
              raise TypeError.new("Return type mismatch: expected #{expected}, got #{actual}", stmt.line, stmt.col)
            end
          end
        else
          if expected == "Any"
            @lambda_first_return_type ||= "Void"
          elsif expected != "Void"
            raise TypeError.new("Function returns #{expected} but got empty return", stmt.line, stmt.col)
          end
        end
      when AST::IfStmt
        cond_type = check_expr(stmt.condition, scope)
        unless cond_type == "Bool"
          raise TypeError.new("if-condition must be Bool, got #{cond_type}", stmt.line, stmt.col)
        end
        check_block(stmt.then_branch, scope)
        if eb = stmt.else_branch
          case eb
          when AST::Block then check_block(eb, scope)
          when AST::IfStmt then check_stmt(eb, scope)
          end
        end
      when AST::WhileStmt
        cond_type = check_expr(stmt.condition, scope)
        unless cond_type == "Bool"
          raise TypeError.new("while-condition must be Bool, got #{cond_type}", stmt.line, stmt.col)
        end
        check_block(stmt.body, scope)
      when AST::ForStmt
        iter_type = check_expr(stmt.iterable, scope)
        unless iter_type == "Range"
          raise TypeError.new("for-loop iterable must be Range, got #{iter_type}", stmt.line, stmt.col)
        end
        body_scope = Scope.new(scope)
        body_scope.declare(stmt.var_name,
          VarSymbol.new(stmt.var_name, AST::Mutability::Final, "Int"),
          stmt.line, stmt.col)
        stmt.body.statements.each { |s| check_stmt(s, body_scope) }
      when AST::Block
        check_block(stmt, scope)
      end
    end

    private def check_var_decl(decl : AST::VarDecl, scope : Scope)
      init = decl.initializer
      raise TypeError.new("Variable '#{decl.name}' must have an initializer", decl.line, decl.col) if init.nil?

      declared = decl.type_ref ? type_ref_to_fqn(decl.type_ref.not_nil!) : nil

      if declared && init.is_a?(AST::NewExpr)
        ne = init.as(AST::NewExpr)
        if BUILTIN_CONTAINER_NAMES.includes?(ne.type_name) || declared.includes?("<")
          ne.expected_type = declared
        end
      end

      if declared && init.is_a?(AST::MethodCall)
        mc = init.as(AST::MethodCall)
        if mc.receiver.is_a?(AST::Identifier) && mc.name == "new"
          recv_name = mc.receiver.as(AST::Identifier).name
          if {"Channel", "Mutex"}.includes?(recv_name)
            mc.expected_type = declared
          end
        end
      end

      init_type = check_expr(init, scope)
      final_declared = declared || init_type
      unless types_compatible?(final_declared, init_type)
        raise TypeError.new("Cannot initialize '#{decl.name}' (#{final_declared}) with #{init_type}", decl.line, decl.col)
      end
      unless scope.symbols.has_key?(decl.name)
        scope.declare(decl.name,
          VarSymbol.new(decl.name, decl.mutability, final_declared),
          decl.line, decl.col)
      else
        sym = scope.symbols[decl.name]
        if sym.is_a?(VarSymbol)
          sym.as(VarSymbol).type_name = final_declared
        end
      end
    end

    def check_expr(expr : AST::Node, scope : Scope) : String
      case expr
      when AST::IntLiteral    then "Int"
      when AST::FloatLiteral  then "Float"
      when AST::StringLiteral then "String"
      when AST::StringInterp  then check_string_interp(expr, scope); "String"
      when AST::CharLiteral   then "Char"
      when AST::BoolLiteral   then "Bool"
      when AST::Identifier
        sym = scope.lookup(expr.name)
        raise TypeError.new("Undefined identifier '#{expr.name}'", expr.line, expr.col) unless sym
        case sym
        when VarSymbol then sym.as(VarSymbol).type_name
        when TypeSymbol then sym.as(TypeSymbol).fqn
        else
          raise TypeError.new("'#{expr.name}' is not a value", expr.line, expr.col)
        end
      when AST::ThisExpr
        sym = scope.lookup("this").as(VarSymbol)
        sym.type_name
      when AST::BinaryOp
        check_binary(expr, scope)
      when AST::UnaryOp
        check_unary(expr, scope)
      when AST::CallExpr
        check_call(expr, scope)
      when AST::NewExpr
        check_new(expr, scope)
      when AST::MemberAccess
        check_member_access(expr, scope)
      when AST::MethodCall
        check_method_call(expr, scope)
      when AST::MemberAssign
        check_member_assign(expr, scope)
      when AST::RangeExpr
        s = check_expr(expr.start, scope)
        e = check_expr(expr.finish, scope)
        unless s == "Int" && e == "Int"
          raise TypeError.new("Range bounds must be Int, got #{s}..#{e}", expr.line, expr.col)
        end
        "Range"
      when AST::OkExpr
        inner = check_expr(expr.value, scope)
        "Result<#{inner},?>"
      when AST::ErrExpr
        inner = check_expr(expr.value, scope)
        "Result<?,#{inner}>"
      when AST::LambdaExpr
        check_lambda(expr, scope)
      when AST::MethodRef
        check_method_ref(expr, scope)
      when AST::MatchExpr
        check_match(expr, scope)
      else
        raise TypeError.new("Cannot type-check expression: #{expr.class}", expr.line, expr.col)
      end
    end

    private def check_string_interp(expr : AST::StringInterp, scope : Scope)
      expr.parts.each do |part|
        if part.is_a?(AST::InterpExpr)
          check_expr(part.as(AST::InterpExpr).expression, scope)
        end
      end
    end

    private def check_binary(expr : AST::BinaryOp, scope : Scope) : String
      lt = check_expr(expr.left, scope)
      rt = check_expr(expr.right, scope)
      result = case expr.op
               when "+", "-", "*", "/", "%"
                 if expr.op == "+" && lt == "String" && rt == "String"
                   "String"
                 elsif !(TypeSystem.numeric?(lt) && TypeSystem.numeric?(rt))
                   raise TypeError.new("Operator '#{expr.op}' requires numeric operands, got #{lt} and #{rt}", expr.line, expr.col)
                 else
                   TypeSystem.promote_numeric(lt, rt)
                 end
               when "==", "!="
                 unless types_compatible?(lt, rt) || types_compatible?(rt, lt)
                   raise TypeError.new("Cannot compare #{lt} with #{rt}", expr.line, expr.col)
                 end
                 "Bool"
               when "<", ">", "<=", ">="
                 unless TypeSystem.numeric?(lt) && TypeSystem.numeric?(rt)
                   raise TypeError.new("Comparison '#{expr.op}' requires numeric operands, got #{lt} and #{rt}", expr.line, expr.col)
                 end
                 "Bool"
               when "&&", "||"
                 unless lt == "Bool" && rt == "Bool"
                   raise TypeError.new("Logical '#{expr.op}' requires Bool operands, got #{lt} and #{rt}", expr.line, expr.col)
                 end
                 "Bool"
               when ".."
                 unless lt == "Int" && rt == "Int"
                   raise TypeError.new("Range bounds must be Int, got #{lt}..#{rt}", expr.line, expr.col)
                 end
                 "Range"
               else
                 raise TypeError.new("Unknown binary operator '#{expr.op}'", expr.line, expr.col)
               end
      expr.result_type = result
      result
    end

    private def check_unary(expr : AST::UnaryOp, scope : Scope) : String
      t = check_expr(expr.operand, scope)
      case expr.op
      when "-", "+"
        unless TypeSystem.numeric?(t)
          raise TypeError.new("Unary '#{expr.op}' requires numeric operand, got #{t}", expr.line, expr.col)
        end
        t
      when "!"
        unless t == "Bool"
          raise TypeError.new("Unary '!' requires Bool, got #{t}", expr.line, expr.col)
        end
        "Bool"
      else
        raise TypeError.new("Unknown unary operator '#{expr.op}'", expr.line, expr.col)
      end
    end

    private def check_call(expr : AST::CallExpr, scope : Scope) : String
      raw = if expr.namespace_path.empty?
              scope.lookup(expr.callee) || @resolver.namespace_resolver.resolve_function_simple(expr.callee, @current_namespace, expr.line, expr.col)
            else
              @resolver.namespace_resolver.resolve_function_qualified(expr.namespace_path, expr.callee, expr.line, expr.col)
            end
      raise TypeError.new("Undefined function '#{expr.callee}'", expr.line, expr.col) unless raw

      if raw.is_a?(VarSymbol)
        var_type = raw.as(VarSymbol).type_name
        unless var_type.starts_with?("Fn(")
          raise TypeError.new("'#{expr.callee}' has type #{var_type}, not callable", expr.line, expr.col)
        end
        param_types, ret_type = TypeSystem.parse_fn_type_string(var_type)

        unless expr.args.size == param_types.size
          raise TypeError.new("'#{expr.callee}' expects #{param_types.size} arguments, got #{expr.args.size}",
            expr.line, expr.col)
        end
        expr.args.each_with_index do |arg, i|
          actual = check_expr(arg, scope)
          expected = param_types[i]
          unless types_compatible?(expected, actual)
            raise TypeError.new("Argument #{i + 1} of '#{expr.callee}': expected #{expected}, got #{actual}",
              arg.line, arg.col)
          end
        end
        return ret_type
      end

      sym = raw.as(FunctionSymbol)

      if sym.param_types == ["Any"]
        unless expr.args.size == 1
          raise TypeError.new("Function '#{expr.callee}' expects 1 argument, got #{expr.args.size}", expr.line, expr.col)
        end
        check_expr(expr.args[0], scope)
        return sym.return_type
      end

      unless expr.args.size == sym.param_types.size
        raise TypeError.new("Function '#{expr.callee}' expects #{sym.param_types.size} arguments, got #{expr.args.size}",
          expr.line, expr.col)
      end
      expr.args.each_with_index do |arg, i|
        actual = check_expr(arg, scope)
        expected = sym.param_types[i]
        unless types_compatible?(expected, actual)
          raise TypeError.new("Argument #{i + 1} of '#{expr.callee}': expected #{expected}, got #{actual}",
            arg.line, arg.col)
        end
      end
      sym.return_type
    end

    private def check_new(expr : AST::NewExpr, scope : Scope) : String
      if BUILTIN_CONTAINER_NAMES.includes?(expr.type_name)
        unless expr.args.empty?
          raise TypeError.new("#{expr.type_name}() constructor takes no arguments", expr.line, expr.col)
        end
        if expr.expected_type.empty?
          raise TypeError.new("Cannot infer type arguments for #{expr.type_name}(); declare the variable type explicitly",
            expr.line, expr.col)
        end
        return expr.expected_type
      end

      fqn = if expr.namespace_path.empty?
              @resolver.namespace_resolver.resolve_type_simple(expr.type_name, @current_namespace, expr.line, expr.col)
            else
              @resolver.namespace_resolver.resolve_type_qualified(expr.namespace_path, expr.type_name, expr.line, expr.col)
            end
      info = @resolver.registry[fqn].not_nil!

      arg_types = expr.args.map { |a| check_expr(a, scope) }

      if !info.type_params.empty?
        if !expr.expected_type.empty?
          base, subs = base_type_and_subs(expr.expected_type)
          if base == fqn
            info.constructors.each do |ctor|
              next if ctor.param_types.size != arg_types.size
              all_match = true
              ctor.param_types.each_with_index do |pt, i|
                substituted = apply_subs(pt, subs)
                unless types_compatible?(substituted, arg_types[i])
                  all_match = false
                  break
                end
              end
              return expr.expected_type if all_match
            end
          end
        end

        info.constructors.each do |ctor|
          next if ctor.param_types.size != arg_types.size
          subs = {} of String => String
          all_match = true
          ctor.param_types.each_with_index do |pt, i|
            if info.type_params.includes?(pt)
              if existing = subs[pt]?
                unless existing == arg_types[i]
                  all_match = false
                  break
                end
              else
                subs[pt] = arg_types[i]
              end
            else
              substituted = apply_subs(pt, subs)
              unless types_compatible?(substituted, arg_types[i])
                all_match = false
                break
              end
            end
          end
          if all_match && subs.size == info.type_params.size
            args_filled = info.type_params.map { |p| subs[p] }.join(",")
            return "#{fqn}<#{args_filled}>"
          end
        end

        raise TypeError.new(
          "Cannot infer type arguments for generic #{fqn}; declare the variable type explicitly",
          expr.line, expr.col
        )
      end

      info.constructors.each do |ctor|
        next if ctor.param_types.size != arg_types.size
        all_match = true
        ctor.param_types.each_with_index do |pt, i|
          unless types_compatible?(pt, arg_types[i])
            all_match = false
            break
          end
        end
        return fqn if all_match
      end

      raise TypeError.new(
        "No matching constructor for #{fqn}(#{arg_types.join(", ")})",
        expr.line, expr.col
      )
    end

    private def base_type_and_subs(type : String) : Tuple(String, Hash(String, String))
      subs = {} of String => String
      return {type, subs} unless type.includes?("<")

      gen_open = type.index("<").not_nil!
      base_name = type[0...gen_open]
      args_str = type[(gen_open + 1)..-2]
      args = split_top_level(args_str)

      info = @resolver.registry[base_name]
      return {type, subs} unless info
      info.type_params.each_with_index do |param, i|
        subs[param] = args[i]? || "?"
      end
      {base_name, subs}
    end

    private def split_top_level(s : String) : Array(String)
      result = [] of String
      depth = 0
      current = String.build do |sb|
      end
      buf = ""
      s.each_char do |c|
        case c
        when '<' then depth += 1; buf += c.to_s
        when '>' then depth -= 1; buf += c.to_s
        when ','
          if depth == 0
            result << buf.strip
            buf = ""
          else
            buf += c.to_s
          end
        else
          buf += c.to_s
        end
      end
      result << buf.strip unless buf.empty?
      result
    end

    private def apply_subs(type : String, subs : Hash(String, String)) : String
      return type if subs.empty?
      result = type
      subs.each do |k, v|
        result = substitute_type_var(result, k, v)
      end
      result
    end

    private def substitute_type_var(type : String, var : String, replacement : String) : String
      result = ""
      i = 0
      while i < type.size
        if i + var.size <= type.size && type[i, var.size] == var
          before_ok = i == 0 || !alphanum_or_under?(type[i - 1])
          after_ok = i + var.size == type.size || !alphanum_or_under?(type[i + var.size])
          if before_ok && after_ok
            result += replacement
            i += var.size
            next
          end
        end
        result += type[i].to_s
        i += 1
      end
      result
    end

    private def alphanum_or_under?(c : Char) : Bool
      c.ascii_alphanumeric? || c == '_'
    end

    private def check_member_access(expr : AST::MemberAccess, scope : Scope) : String
      receiver_type = check_expr(expr.receiver, scope)
      base, subs = base_type_and_subs(receiver_type)
      info = @resolver.registry[base]
      unless info
        raise TypeError.new("Cannot access member '#{expr.name}' on type #{receiver_type}", expr.line, expr.col)
      end
      f = @resolver.registry.lookup_field(base, expr.name)
      if f
        return apply_subs(f.type_name, subs)
      end
      raise TypeError.new("Type #{receiver_type} has no field '#{expr.name}'", expr.line, expr.col)
    end

    private def check_method_call(expr : AST::MethodCall, scope : Scope) : String
      if expr.receiver.is_a?(AST::Identifier)
        recv_id = expr.receiver.as(AST::Identifier)
        sym = scope.lookup(recv_id.name)
        if sym.is_a?(TypeSymbol) && sym.as(TypeSymbol).kind == "builtin"
          return check_static_builtin_call(expr, recv_id.name, scope)
        end
      end

      receiver_type = check_expr(expr.receiver, scope)
      expr.receiver_type = receiver_type

      if conc_ret = check_concurrency_instance_method(expr, receiver_type, scope)
        return conc_ret
      end

      if methods = BuiltinMethods.for_type(receiver_type)
        m = methods[expr.name]?
        if m
          unless expr.args.size == m.param_types.size
            raise TypeError.new(
              "Method '#{expr.name}' on #{receiver_type} expects #{m.param_types.size} arguments, got #{expr.args.size}",
              expr.line, expr.col)
          end
          inferred_substitutions = {} of String => String
          expr.args.each_with_index do |arg, i|
            actual = check_expr(arg, scope)
            expected = m.param_types[i]
            if expected == "?"
              inferred_substitutions["?"] = actual
            elsif expected.includes?("?")
              expected = substitute_placeholders(expected, inferred_substitutions, actual)
            end
            unless types_compatible?(expected, actual) || expected.includes?("?")
              raise TypeError.new("Argument #{i + 1} of '#{expr.name}': expected #{expected}, got #{actual}",
                arg.line, arg.col)
            end
          end
          ret = m.return_type
          if ret.includes?("?")
            inferred_substitutions.each do |k, v|
              ret = ret.gsub("?", v)
            end
          end
          return ret
        end
        raise TypeError.new("Type #{receiver_type} has no method '#{expr.name}'", expr.line, expr.col)
      end

      base, subs = base_type_and_subs(receiver_type)
      info = @resolver.registry[base]
      unless info
        raise TypeError.new("Cannot call method '#{expr.name}' on type #{receiver_type}", expr.line, expr.col)
      end
      m = @resolver.registry.lookup_method(base, expr.name)
      unless m
        raise TypeError.new("Type #{receiver_type} has no method '#{expr.name}'", expr.line, expr.col)
      end
      unless expr.args.size == m.param_types.size
        raise TypeError.new(
          "Method '#{expr.name}' expects #{m.param_types.size} arguments, got #{expr.args.size}",
          expr.line, expr.col)
      end
      expr.args.each_with_index do |arg, i|
        actual = check_expr(arg, scope)
        expected = apply_subs(m.param_types[i], subs)
        unless types_compatible?(expected, actual)
          raise TypeError.new("Argument #{i + 1} of '#{expr.name}': expected #{expected}, got #{actual}",
            arg.line, arg.col)
        end
      end
      apply_subs(m.return_type, subs)
    end

    private def substitute_placeholders(template : String, subs : Hash(String, String), latest : String) : String
      result = template
      subs.each do |k, v|
        result = result.gsub("?", v)
      end
      if result.includes?("?")
        result = result.gsub("?", latest)
      end
      result
    end

    private def check_static_builtin_call(expr : AST::MethodCall, type_name : String, scope : Scope) : String
      case {type_name, expr.name}
      when {"Fiber", "spawn"}, {"Thread", "spawn"}, {"VirtualThread", "spawn"}
        unless expr.args.size == 1
          raise TypeError.new("#{type_name}.spawn expects 1 lambda argument, got #{expr.args.size}",
            expr.line, expr.col)
        end
        arg_type = check_expr(expr.args[0], scope)
        unless arg_type.starts_with?("Fn(")
          raise TypeError.new("#{type_name}.spawn requires a lambda, got #{arg_type}",
            expr.line, expr.col)
        end
        params, ret = TypeSystem.parse_fn_type_string(arg_type)
        unless params.empty?
          raise TypeError.new("#{type_name}.spawn lambda must take no arguments",
            expr.line, expr.col)
        end
        expr.receiver_type = type_name
        return "#{type_name}<#{ret}>"
      when {"Mutex", "new"}
        unless expr.args.empty?
          raise TypeError.new("Mutex.new takes no arguments", expr.line, expr.col)
        end
        expr.receiver_type = "Mutex"
        return "Mutex"
      when {"Channel", "new"}
        unless expr.args.empty?
          raise TypeError.new("Channel.new takes no arguments", expr.line, expr.col)
        end
        result = expr.expected_type.empty? ? "Channel<?>" : expr.expected_type
        expr.receiver_type = result
        return result
      else
        raise TypeError.new("'#{type_name}' has no static method '#{expr.name}'",
          expr.line, expr.col)
      end
    end

    private def check_concurrency_instance_method(expr : AST::MethodCall, receiver_type : String, scope : Scope) : String?
      if receiver_type.starts_with?("Fiber<") || receiver_type.starts_with?("Thread<") || receiver_type.starts_with?("VirtualThread<")
        case expr.name
        when "await"
          unless expr.args.empty?
            raise TypeError.new("await() takes no arguments", expr.line, expr.col)
          end
          inner = receiver_type[(receiver_type.index("<").not_nil! + 1)..-2]
          return inner
        end
      elsif receiver_type == "Mutex"
        case expr.name
        when "lock", "unlock"
          unless expr.args.empty?
            raise TypeError.new("#{expr.name}() takes no arguments", expr.line, expr.col)
          end
          return "Void"
        when "synchronize"
          unless expr.args.size == 1
            raise TypeError.new("synchronize requires 1 lambda argument", expr.line, expr.col)
          end
          arg_type = check_expr(expr.args[0], scope)
          unless arg_type.starts_with?("Fn(")
            raise TypeError.new("synchronize requires a lambda", expr.line, expr.col)
          end
          _params, ret = TypeSystem.parse_fn_type_string(arg_type)
          return ret
        end
      elsif receiver_type.starts_with?("Channel<")
        inner = receiver_type[(receiver_type.index("<").not_nil! + 1)..-2]
        case expr.name
        when "send"
          unless expr.args.size == 1
            raise TypeError.new("send requires 1 argument", expr.line, expr.col)
          end
          actual = check_expr(expr.args[0], scope)
          if inner != "?"
            unless types_compatible?(inner, actual)
              raise TypeError.new("send: expected #{inner}, got #{actual}", expr.line, expr.col)
            end
          end
          return "Void"
        when "receive"
          unless expr.args.empty?
            raise TypeError.new("receive() takes no arguments", expr.line, expr.col)
          end
          return inner
        when "close"
          return "Void"
        end
      end
      nil
    end

    private def check_member_assign(expr : AST::MemberAssign, scope : Scope) : String
      receiver_type = check_expr(expr.receiver, scope)
      base, subs = base_type_and_subs(receiver_type)
      info = @resolver.registry[base]
      unless info
        raise TypeError.new("Cannot assign to member of #{receiver_type}", expr.line, expr.col)
      end
      f = @resolver.registry.lookup_field(base, expr.name)
      unless f
        raise TypeError.new("Type #{receiver_type} has no field '#{expr.name}'", expr.line, expr.col)
      end
      value_type = check_expr(expr.value, scope)
      field_type = apply_subs(f.type_name, subs)
      unless types_compatible?(field_type, value_type)
        raise TypeError.new("Cannot assign #{value_type} to field '#{expr.name}' of type #{field_type}",
          expr.line, expr.col)
      end
      field_type
    end

    private def check_lambda(expr : AST::LambdaExpr, scope : Scope) : String
      lambda_scope = Scope.new(scope)
      expr.params.each do |p|
        lambda_scope.declare(p.name,
          VarSymbol.new(p.name, AST::Mutability::Mutable, type_ref_to_fqn(p.type_ref)),
          p.line, p.col)
      end
      body = expr.body
      ret_type : String
      if body.is_a?(AST::Block)
        block = body.as(AST::Block)
        saved = @current_function_return
        @current_function_return = "Any"
        @lambda_first_return_type = nil
        block.statements.each { |s| check_stmt(s, lambda_scope) }
        if @lambda_first_return_type
          ret_type = @lambda_first_return_type.not_nil!
        elsif !block.statements.empty? && block.statements.last.is_a?(AST::ExpressionStmt)
          last_expr = block.statements.last.as(AST::ExpressionStmt).expression
          ret_type = check_expr(last_expr, lambda_scope)
        else
          ret_type = "Void"
        end
        @lambda_first_return_type = nil
        @current_function_return = saved
      else
        ret_type = check_expr(body, lambda_scope)
      end
      param_str = expr.params.map { |p| type_ref_to_fqn(p.type_ref) }.join(",")
      "Fn(#{param_str}):#{ret_type}"
    end

    private def check_method_ref(expr : AST::MethodRef, scope : Scope) : String
      if tn = expr.type_name
        info = @resolver.registry[tn] || @resolver.registry[
          @resolver.namespace_resolver.resolve_type_simple(tn, @current_namespace, expr.line, expr.col)
        ]
        unless info
          raise TypeError.new("Unknown type '#{tn}' in method reference", expr.line, expr.col)
        end
        m = @resolver.registry.lookup_method(info.fqn, expr.method_name)
        unless m
          raise TypeError.new("Type '#{tn}' has no method '#{expr.method_name}'", expr.line, expr.col)
        end
        params = [info.fqn] + m.param_types
        "Fn(#{params.join(",")}):#{m.return_type}"
      elsif recv = expr.receiver
        recv_type = check_expr(recv, scope)
        m = @resolver.registry.lookup_method(recv_type, expr.method_name)
        unless m
          raise TypeError.new("Type '#{recv_type}' has no method '#{expr.method_name}'", expr.line, expr.col)
        end
        "Fn(#{m.param_types.join(",")}):#{m.return_type}"
      else
        raise TypeError.new("Invalid method reference", expr.line, expr.col)
      end
    end

    private def check_match(expr : AST::MatchExpr, scope : Scope) : String
      subject_type = check_expr(expr.subject, scope)
      expr.subject_type = subject_type

      arm_types = [] of String
      expr.arms.each do |arm|
        arm_scope = Scope.new(scope)
        arm.patterns.each { |p| check_pattern(p, subject_type, arm_scope) }
        if guard = arm.guard
          gt = check_expr(guard, arm_scope)
          unless gt == "Bool"
            raise TypeError.new("Guard expression must be Bool, got #{gt}", arm.line, arm.col)
          end
        end
        body = arm.body
        if body.is_a?(AST::Block)
          block = body.as(AST::Block)
          saved = @current_function_return
          @current_function_return = "Any"
          @lambda_first_return_type = nil
          block.statements.each { |s| check_stmt(s, arm_scope) }
          arm_types << (@lambda_first_return_type || "Void")
          @lambda_first_return_type = nil
          @current_function_return = saved
        else
          arm_types << check_expr(body, arm_scope)
        end
      end

      return "Void" if arm_types.empty?
      result = arm_types[0]
      arm_types.each do |t|
        next if t == result
        if types_compatible?(result, t)
        elsif types_compatible?(t, result)
          result = t
        elsif result == "Void" || t == "Void"
          result = "Void"
        else
          if result.starts_with?("Result<") && t.starts_with?("Result<")
            result = TypeSystem.unify_result_types(result, t)
          else
            raise TypeError.new("Match arms have incompatible types: #{result} vs #{t}", expr.line, expr.col)
          end
        end
      end
      result
    end

    private def check_pattern(pat : AST::Pattern, subject_type : String, scope : Scope)
      case pat
      when AST::WildcardPattern, AST::NullPattern
      when AST::LiteralPattern
        lit_type = check_expr(pat.value, scope)
        unless types_compatible?(subject_type, lit_type) || types_compatible?(lit_type, subject_type)
          raise TypeError.new("Pattern type #{lit_type} doesn't match subject #{subject_type}", pat.line, pat.col)
        end
      when AST::RangePattern
        st = check_expr(pat.start, scope)
        et = check_expr(pat.finish, scope)
        unless st == "Int" && et == "Int"
          raise TypeError.new("Range pattern bounds must be Int", pat.line, pat.col)
        end
        unless subject_type == "Int"
          raise TypeError.new("Range pattern requires Int subject, got #{subject_type}", pat.line, pat.col)
        end
      when AST::TypePattern
        if b = pat.binding
          unless scope.symbols.has_key?(b)
            scope.declare(b, VarSymbol.new(b, AST::Mutability::Final, pat.type_name), pat.line, pat.col)
          else
            sym = scope.symbols[b]
            sym.as(VarSymbol).type_name = pat.type_name if sym.is_a?(VarSymbol)
          end
        end
      when AST::BindPattern
        unless scope.symbols.has_key?(pat.name)
          scope.declare(pat.name, VarSymbol.new(pat.name, AST::Mutability::Final, subject_type), pat.line, pat.col)
        else
          sym = scope.symbols[pat.name]
          sym.as(VarSymbol).type_name = subject_type if sym.is_a?(VarSymbol)
        end
      when AST::DestructurePattern
        case pat.type_name
        when "Ok"
          unless subject_type.starts_with?("Result<")
            raise TypeError.new("Ok-pattern requires Result subject, got #{subject_type}", pat.line, pat.col)
          end
          inner = TypeSystem.result_inner_ok_type(subject_type)
          unless pat.sub_patterns.size == 1
            raise TypeError.new("Ok-pattern takes exactly 1 sub-pattern", pat.line, pat.col)
          end
          check_pattern(pat.sub_patterns[0], inner, scope)
        when "Err"
          unless subject_type.starts_with?("Result<")
            raise TypeError.new("Err-pattern requires Result subject, got #{subject_type}", pat.line, pat.col)
          end
          inner = TypeSystem.result_inner_err_type(subject_type)
          unless pat.sub_patterns.size == 1
            raise TypeError.new("Err-pattern takes exactly 1 sub-pattern", pat.line, pat.col)
          end
          check_pattern(pat.sub_patterns[0], inner, scope)
        else
          info = @resolver.registry[pat.type_name] || @resolver.registry[
            @resolver.namespace_resolver.resolve_type_simple(pat.type_name, @current_namespace, pat.line, pat.col)
          ]
          unless info
            raise TypeError.new("Unknown type '#{pat.type_name}' in pattern", pat.line, pat.col)
          end
          unless info.is_data
            raise TypeError.new("Destructuring only works on data classes, '#{pat.type_name}' isn't one", pat.line, pat.col)
          end
          fields = info.fields.values.to_a
          unless pat.sub_patterns.size == fields.size
            raise TypeError.new(
              "Pattern #{pat.type_name}(...) expects #{fields.size} fields, got #{pat.sub_patterns.size}",
              pat.line, pat.col)
          end
          pat.sub_patterns.each_with_index do |sub, i|
            check_pattern(sub, fields[i].type_name, scope)
          end
          unless types_compatible?(subject_type, info.fqn)
            raise TypeError.new("Pattern #{pat.type_name} can't match subject of type #{subject_type}", pat.line, pat.col)
          end
        end
      end
    end

    private def types_compatible?(expected : String, actual : String) : Bool
      return true if expected == actual
      return true if expected == "Any" || actual == "Any"
      return true if expected == "Float" && actual == "Int"

      if expected.starts_with?("Result<") && actual.starts_with?("Result<")
        e_inner = expected[7..-2]
        a_inner = actual[7..-2]
        e_parts = e_inner.split(",", 2)
        a_parts = a_inner.split(",", 2)
        if e_parts.size == 2 && a_parts.size == 2
          ok_match  = e_parts[0] == "?" || a_parts[0] == "?" || types_compatible?(e_parts[0], a_parts[0])
          err_match = e_parts[1] == "?" || a_parts[1] == "?" || types_compatible?(e_parts[1], a_parts[1])
          return ok_match && err_match
        end
      end

      if expected.starts_with?("Fn(") && actual.starts_with?("Fn(")
        return expected == actual
      end

      if expected.includes?("<") && actual.includes?("<")
        exp_lt = expected.index("<").not_nil!
        act_lt = actual.index("<").not_nil!
        if expected[0...exp_lt] == actual[0...act_lt]
          exp_args = expected[(exp_lt + 1)..-2]
          act_args = actual[(act_lt + 1)..-2]
          return true if exp_args == "?" || act_args == "?"
        end
      end

      if @resolver.registry[actual] && @resolver.registry[expected]
        return @resolver.registry.assignable?(actual, expected)
      end
      false
    end

    private def type_ref_to_fqn(ref : AST::TypeRef) : String
      case ref
      when AST::NamedType
        nt = ref.as(AST::NamedType)
        return nt.name if Resolver::BUILTIN_TYPES.includes?(nt.name)
        return nt.name if RESERVED_NAMES.includes?(nt.name)
        return nt.name if BUILTIN_CONTAINER_NAMES.includes?(nt.name)
        return nt.name if @current_type_params.includes?(nt.name)
        @resolver.namespace_resolver.resolve_type_simple(nt.name, @current_namespace, nt.line, nt.col)
      when AST::GenericType
        gt = ref.as(AST::GenericType)
        args = gt.type_args.map { |a| type_ref_to_fqn(a) }.join(",")
        "#{gt.name}<#{args}>"
      when AST::FunctionType
        ft = ref.as(AST::FunctionType)
        params = ft.param_types.map { |p| type_ref_to_fqn(p) }.join(",")
        "Fn(#{params}):#{type_ref_to_fqn(ft.return_type)}"
      else
        "Unknown"
      end
    end
  end
end
