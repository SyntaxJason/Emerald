require "../frontend/ast"
require "./scope"
require "./registry"
require "./namespace"
require "./type_system"
require "./builtin_functions"

module Emerald
  class Resolver
    getter global_scope : Scope
    getter registry : ClassRegistry
    getter namespace_resolver : NamespaceResolver

    def initialize
      @global_scope = Scope.new
      @registry = ClassRegistry.new
      @namespace_resolver = NamespaceResolver.new(@registry)
      @current_namespace = ""
      @current_type_params = [] of String
      register_builtins
    end

    private def register_builtins
      println_sym = FunctionSymbol.new("println", ["Any"], "Void", "println")
      print_sym = FunctionSymbol.new("print", ["Any"], "Void", "print")
      @global_scope.declare("println", println_sym, 0, 0)
      @global_scope.declare("print", print_sym, 0, 0)
      @namespace_resolver.add_function("println", println_sym)
      @namespace_resolver.add_function("print", print_sym)

      BuiltinFunctions.all.each do |fqn, bf|
        simple = fqn.split("::").last
        sym = FunctionSymbol.new(simple, bf.param_types, bf.return_type, fqn)
        @namespace_resolver.add_function(fqn, sym)
      end

      ["Fiber", "Thread", "VirtualThread", "Channel"].each do |name|
        @global_scope.declare(name, TypeSymbol.new(name, "builtin", name), 0, 0)
      end
      @global_scope.declare("Mutex", TypeSymbol.new("Mutex", "builtin", "Mutex"), 0, 0)
    end

    def resolve(program : AST::Program)
      ns = if decl = program.namespace_decl
             decl.to_s
           else
             DEFAULT_ROOT_NAMESPACE
           end
      assign_namespaces(program, ns)
      program.declarations.each { |d| collect_declaration(d, ns) }
      program.declarations.each { |d| collect_class_members(d) }
      program.declarations.each { |d| resolve_declaration(d, ns) }
    end

    private def assign_namespaces(program : AST::Program, ns : String)
      program.declarations.each do |d|
        case d
        when AST::ClassDecl     then d.namespace = ns
        when AST::InterfaceDecl then d.namespace = ns
        end
      end
    end

    private def fqn_of(simple : String, ns : String) : String
      ns.empty? ? simple : "#{ns}::#{simple}"
    end

    private def collect_declaration(decl : AST::Node, ns : String)
      case decl
      when AST::FunctionDecl
        check_reserved!(decl.name, decl.line, decl.col)
        decl_ns = decl.namespace.empty? ? ns : decl.namespace
        fqn = fqn_of(decl.name, decl_ns)
        param_types = decl.params.map { |p| TypeSystem.type_ref_name(p.type_ref) }
        ret = TypeSystem.type_ref_name(decl.return_type)
        sym = FunctionSymbol.new(decl.name, param_types, ret, fqn)
        unless @global_scope.symbols.has_key?(decl.name)
          @global_scope.declare(decl.name, sym, decl.line, decl.col)
        end
        @namespace_resolver.add_function(fqn, sym)
      when AST::ClassDecl
        check_reserved!(decl.name, decl.line, decl.col)
        fqn = fqn_of(decl.name, ns)
        info = ClassInfo.new(decl.name, fqn, decl.is_data, decl.is_abstract, false)
        info.type_params = decl.type_params.dup
        @registry.register(info, decl.line, decl.col)
        type_sym = TypeSymbol.new(decl.name, decl.is_data ? "data" : "class", fqn)
        unless @global_scope.symbols.has_key?(decl.name)
          @global_scope.declare(decl.name, type_sym, decl.line, decl.col)
        end
      when AST::InterfaceDecl
        check_reserved!(decl.name, decl.line, decl.col)
        fqn = fqn_of(decl.name, ns)
        info = ClassInfo.new(decl.name, fqn, false, false, true)
        info.type_params = decl.type_params.dup
        @registry.register(info, decl.line, decl.col)
        type_sym = TypeSymbol.new(decl.name, "interface", fqn)
        unless @global_scope.symbols.has_key?(decl.name)
          @global_scope.declare(decl.name, type_sym, decl.line, decl.col)
        end
      when AST::AliasDecl
        target_fqn = decl.target.to_s
        @namespace_resolver.add_alias(decl.name, target_fqn, decl.line, decl.col)
      end
    end

    private def check_reserved!(name : String, line : Int32, col : Int32)
      if RESERVED_NAMES.includes?(name)
        raise ResolveError.new("'#{name}' is a reserved name and cannot be redefined", line, col)
      end
    end

    private def collect_class_members(decl : AST::Node)
      case decl
      when AST::ClassDecl
        info = @registry[fqn_of(decl.name, decl.namespace)].not_nil!
        saved = @current_type_params
        @current_type_params = decl.type_params
        info.base = decl.base ? resolve_type_name(decl.base.not_nil!, decl.namespace, decl.line, decl.col) : nil
        info.interfaces = decl.interfaces.map { |i| resolve_type_name(i, decl.namespace, decl.line, decl.col) }

        decl.fields.each do |f|
          info.fields[f.name] = FieldInfo.new(f.name, type_ref_to_fqn(f.type_ref, decl.namespace), f.visibility)
        end
        decl.methods.each do |m|
          info.methods[m.name] = MethodInfo.new(
            m.name,
            m.params.map { |p| type_ref_to_fqn(p.type_ref, decl.namespace) },
            type_ref_to_fqn(m.return_type, decl.namespace),
            m.visibility,
            m.is_abstract
          )
        end

        if decl.is_data && decl.constructors.empty?
          info.constructors << ConstructorInfo.new(
            decl.fields.map { |f| type_ref_to_fqn(f.type_ref, decl.namespace) },
            AST::Visibility::Public
          )
        end

        decl.constructors.each do |c|
          info.constructors << ConstructorInfo.new(
            c.params.map { |p| type_ref_to_fqn(p.type_ref, decl.namespace) },
            c.visibility
          )
        end

        if info.constructors.empty?
          empty = [] of String
          info.constructors << ConstructorInfo.new(empty, AST::Visibility::Public)
        end

        if decl.is_data
          info.methods["equals"] = MethodInfo.new(
            "equals", [info.fqn], "Bool", AST::Visibility::Public, false
          )
          info.methods["copy"] = MethodInfo.new(
            "copy",
            decl.fields.map { |f| type_ref_to_fqn(f.type_ref, decl.namespace) },
            info.fqn,
            AST::Visibility::Public, false
          )
        end
        @current_type_params = saved
      when AST::InterfaceDecl
        info = @registry[fqn_of(decl.name, decl.namespace)].not_nil!
        info.interfaces = decl.extends_interfaces.map { |i| resolve_type_name(i, decl.namespace, decl.line, decl.col) }
        decl.methods.each do |m|
          info.methods[m.name] = MethodInfo.new(
            m.name,
            m.params.map { |p| type_ref_to_fqn(p.type_ref, decl.namespace) },
            type_ref_to_fqn(m.return_type, decl.namespace),
            m.visibility,
            m.body.nil?
          )
        end
      end
    end

    private def type_ref_to_fqn(ref : AST::TypeRef, current_ns : String) : String
      case ref
      when AST::NamedType
        nt = ref.as(AST::NamedType)
        return nt.name if BUILTIN_TYPES.includes?(nt.name)
        return nt.name if RESERVED_NAMES.includes?(nt.name)
        return nt.name if BUILTIN_CONTAINER_NAMES.includes?(nt.name)
        return nt.name if @current_type_params.includes?(nt.name)
        resolve_type_name(nt.name, current_ns, nt.line, nt.col)
      when AST::GenericType
        gt = ref.as(AST::GenericType)
        args = gt.type_args.map { |a| type_ref_to_fqn(a, current_ns) }.join(",")
        "#{gt.name}<#{args}>"
      when AST::FunctionType
        ft = ref.as(AST::FunctionType)
        params = ft.param_types.map { |p| type_ref_to_fqn(p, current_ns) }.join(",")
        "Fn(#{params}):#{type_ref_to_fqn(ft.return_type, current_ns)}"
      else
        "Unknown"
      end
    end

    BUILTIN_TYPES = ["Int", "Float", "Bool", "Char", "String", "Void", "Any", "Range"]

    private def resolve_type_name(name : String, current_ns : String, line : Int32, col : Int32) : String
      return name if BUILTIN_TYPES.includes?(name)
      return name if RESERVED_NAMES.includes?(name)
      return name if BUILTIN_CONTAINER_NAMES.includes?(name)
      return name if @current_type_params.includes?(name)
      @namespace_resolver.resolve_type_simple(name, current_ns, line, col)
    end

    private def resolve_declaration(decl : AST::Node, ns : String)
      case decl
      when AST::FunctionDecl
        fn_scope = Scope.new(@global_scope)
        decl.params.each do |p|
          fn_scope.declare(p.name,
            VarSymbol.new(p.name, AST::Mutability::Mutable, type_ref_to_fqn(p.type_ref, ns)),
            p.line, p.col)
        end
        @current_namespace = ns
        resolve_block(decl.body, fn_scope)
      when AST::MainDecl
        @current_namespace = ns
        main_scope = Scope.new(@global_scope)
        resolve_block(decl.body, main_scope)
      when AST::ClassDecl
        @current_namespace = ns
        resolve_class(decl)
      when AST::InterfaceDecl
        @current_namespace = ns
        resolve_interface(decl)
      when AST::VarDecl
        @current_namespace = ns
        resolve_var_decl(decl, @global_scope)
      when AST::AliasDecl
      else
        @current_namespace = ns
        resolve_stmt(decl, @global_scope)
      end
    end

    private def resolve_class(decl : AST::ClassDecl)
      saved_tp = @current_type_params
      @current_type_params = decl.type_params
      validate_base_and_interfaces(decl)

      decl.fields.each do |f|
        if init = f.initializer
          resolve_expr(init, @global_scope)
        end
      end

      decl.constructors.each do |ctor|
        ctor_scope = Scope.new(@global_scope)
        ctor_scope.declare("this",
          VarSymbol.new("this", AST::Mutability::Final, fqn_of(decl.name, decl.namespace)),
          ctor.line, ctor.col)
        ctor.params.each do |p|
          ctor_scope.declare(p.name,
            VarSymbol.new(p.name, AST::Mutability::Mutable, type_ref_to_fqn(p.type_ref, decl.namespace)),
            p.line, p.col)
        end
        resolve_block(ctor.body, ctor_scope)
      end

      decl.methods.each do |m|
        next if m.is_abstract
        body = m.body
        next if body.nil?

        m_scope = Scope.new(@global_scope)
        m_scope.declare("this",
          VarSymbol.new("this", AST::Mutability::Final, fqn_of(decl.name, decl.namespace)),
          m.line, m.col)
        m.params.each do |p|
          m_scope.declare(p.name,
            VarSymbol.new(p.name, AST::Mutability::Mutable, type_ref_to_fqn(p.type_ref, decl.namespace)),
            p.line, p.col)
        end
        resolve_block(body, m_scope)
      end
      @current_type_params = saved_tp
    end

    private def resolve_interface(decl : AST::InterfaceDecl)
      decl.methods.each do |m|
        next unless m.is_default
        body = m.body
        next if body.nil?
        m_scope = Scope.new(@global_scope)
        m_scope.declare("this",
          VarSymbol.new("this", AST::Mutability::Final, fqn_of(decl.name, decl.namespace)),
          m.line, m.col)
        m.params.each do |p|
          m_scope.declare(p.name,
            VarSymbol.new(p.name, AST::Mutability::Mutable, type_ref_to_fqn(p.type_ref, decl.namespace)),
            p.line, p.col)
        end
        resolve_block(body, m_scope)
      end
    end

    private def validate_base_and_interfaces(decl : AST::ClassDecl)
      if base = decl.base
        info = @registry[resolve_type_name(base, decl.namespace, decl.line, decl.col)]
        unless info
          raise ResolveError.new("Unknown base class '#{base}'", decl.line, decl.col)
        end
        if info.is_interface
          raise ResolveError.new("Cannot extend interface '#{base}' (use implements)", decl.line, decl.col)
        end
      end
      decl.interfaces.each do |iface|
        info = @registry[resolve_type_name(iface, decl.namespace, decl.line, decl.col)]
        unless info
          raise ResolveError.new("Unknown interface '#{iface}'", decl.line, decl.col)
        end
        unless info.is_interface
          raise ResolveError.new("'#{iface}' is not an interface", decl.line, decl.col)
        end
      end
    end

    private def resolve_block(block : AST::Block, parent : Scope)
      scope = Scope.new(parent)
      block.statements.each { |stmt| resolve_stmt(stmt, scope) }
    end

    private def resolve_stmt(stmt : AST::Node, scope : Scope)
      case stmt
      when AST::VarDecl
        resolve_var_decl(stmt, scope)
      when AST::AssignStmt
        sym = scope.lookup(stmt.target)
        unless sym
          raise ResolveError.new("Undefined variable '#{stmt.target}'", stmt.line, stmt.col)
        end
        unless sym.is_a?(VarSymbol)
          raise ResolveError.new("'#{stmt.target}' is not a variable", stmt.line, stmt.col)
        end
        if sym.as(VarSymbol).mutability != AST::Mutability::Mutable
          raise ResolveError.new("Cannot assign to '#{stmt.target}' (immutable)", stmt.line, stmt.col)
        end
        resolve_expr(stmt.value, scope)
      when AST::ExpressionStmt
        resolve_expr(stmt.expression, scope)
      when AST::ReturnStmt
        if v = stmt.value
          resolve_expr(v, scope)
        end
      when AST::IfStmt
        resolve_expr(stmt.condition, scope)
        resolve_block(stmt.then_branch, scope)
        if eb = stmt.else_branch
          case eb
          when AST::Block then resolve_block(eb, scope)
          when AST::IfStmt then resolve_stmt(eb, scope)
          end
        end
      when AST::WhileStmt
        resolve_expr(stmt.condition, scope)
        resolve_block(stmt.body, scope)
      when AST::ForStmt
        resolve_expr(stmt.iterable, scope)
        body_scope = Scope.new(scope)
        body_scope.declare(stmt.var_name,
          VarSymbol.new(stmt.var_name, AST::Mutability::Final, "Int"),
          stmt.line, stmt.col)
        stmt.body.statements.each { |s| resolve_stmt(s, body_scope) }
      when AST::Block
        resolve_block(stmt, scope)
      end
    end

    private def resolve_var_decl(decl : AST::VarDecl, scope : Scope)
      if init = decl.initializer
        resolve_expr(init, scope)
      end
      type_name = decl.type_ref ? type_ref_to_fqn(decl.type_ref.not_nil!, @current_namespace) : "?"
      scope.declare(decl.name,
        VarSymbol.new(decl.name, decl.mutability, type_name),
        decl.line, decl.col)
    end

    private def resolve_expr(expr : AST::Node, scope : Scope)
      case expr
      when AST::Identifier
        if expr.namespace_path.empty?
          sym = scope.lookup(expr.name)
          unless sym
            raise ResolveError.new("Undefined identifier '#{expr.name}'", expr.line, expr.col)
          end
        end
      when AST::CallExpr
        if expr.namespace_path.empty?
          sym = scope.lookup(expr.callee) || @namespace_resolver.resolve_function_simple(expr.callee, @current_namespace, expr.line, expr.col)
          unless sym
            raise ResolveError.new("Undefined function '#{expr.callee}'", expr.line, expr.col)
          end
        else
          @namespace_resolver.resolve_function_qualified(expr.namespace_path, expr.callee, expr.line, expr.col) ||
            raise(ResolveError.new("Undefined function '#{expr.namespace_path.join("::")}::#{expr.callee}'", expr.line, expr.col))
        end
        expr.args.each { |a| resolve_expr(a, scope) }
      when AST::MethodCall
        resolve_expr(expr.receiver, scope)
        expr.args.each { |a| resolve_expr(a, scope) }
      when AST::MemberAccess
        resolve_expr(expr.receiver, scope)
      when AST::MemberAssign
        resolve_expr(expr.receiver, scope)
        resolve_expr(expr.value, scope)
      when AST::ThisExpr
        unless scope.lookup("this")
          raise ResolveError.new("'this' used outside of a method or constructor", expr.line, expr.col)
        end
      when AST::NewExpr
        if BUILTIN_CONTAINER_NAMES.includes?(expr.type_name)
          expr.args.each { |a| resolve_expr(a, scope) }
        else
          fqn = if expr.namespace_path.empty?
                  @namespace_resolver.resolve_type_simple(expr.type_name, @current_namespace, expr.line, expr.col)
                else
                  @namespace_resolver.resolve_type_qualified(expr.namespace_path, expr.type_name, expr.line, expr.col)
                end
          info = @registry[fqn].not_nil!
          if info.is_interface
            raise ResolveError.new("Cannot construct interface '#{expr.type_name}'", expr.line, expr.col)
          end
          if info.is_abstract
            raise ResolveError.new("Cannot construct abstract class '#{expr.type_name}'", expr.line, expr.col)
          end
          expr.args.each { |a| resolve_expr(a, scope) }
        end
      when AST::BinaryOp
        resolve_expr(expr.left, scope)
        resolve_expr(expr.right, scope)
      when AST::UnaryOp
        resolve_expr(expr.operand, scope)
      when AST::RangeExpr
        resolve_expr(expr.start, scope)
        resolve_expr(expr.finish, scope)
      when AST::StringInterp
        expr.parts.each do |part|
          if part.is_a?(AST::InterpExpr)
            resolve_expr(part.as(AST::InterpExpr).expression, scope)
          end
        end
      when AST::OkExpr
        resolve_expr(expr.value, scope)
      when AST::ErrExpr
        resolve_expr(expr.value, scope)
      when AST::LambdaExpr
        lambda_scope = Scope.new(scope)
        expr.params.each do |p|
          lambda_scope.declare(p.name,
            VarSymbol.new(p.name, AST::Mutability::Mutable, type_ref_to_fqn(p.type_ref, @current_namespace)),
            p.line, p.col)
        end
        body = expr.body
        if body.is_a?(AST::Block)
          body.as(AST::Block).statements.each { |s| resolve_stmt(s, lambda_scope) }
        else
          resolve_expr(body, lambda_scope)
        end
      when AST::MethodRef
        if recv = expr.receiver
          resolve_expr(recv, scope)
        end
      when AST::MatchExpr
        resolve_expr(expr.subject, scope)
        expr.arms.each do |arm|
          arm_scope = Scope.new(scope)
          arm.patterns.each { |p| bind_pattern(p, arm_scope) }
          if guard = arm.guard
            resolve_expr(guard, arm_scope)
          end
          body = arm.body
          if body.is_a?(AST::Block)
            body.as(AST::Block).statements.each { |s| resolve_stmt(s, arm_scope) }
          else
            resolve_expr(body, arm_scope)
          end
        end
      end
    end

    private def bind_pattern(pat : AST::Pattern, scope : Scope)
      case pat
      when AST::WildcardPattern, AST::NullPattern, AST::LiteralPattern, AST::RangePattern
      when AST::TypePattern
        if b = pat.binding
          scope.declare(b,
            VarSymbol.new(b, AST::Mutability::Final, pat.type_name),
            pat.line, pat.col)
        end
      when AST::BindPattern
        scope.declare(pat.name,
          VarSymbol.new(pat.name, AST::Mutability::Final, "?"),
          pat.line, pat.col)
      when AST::DestructurePattern
        pat.sub_patterns.each { |sub| bind_pattern(sub, scope) }
      end
    end
  end
end
