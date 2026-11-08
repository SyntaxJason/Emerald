require "../resolver"

module Emerald
  class Resolver
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
      when AST::MacroDecl
      else
        @current_namespace = ns
        resolve_stmt(decl, @global_scope)
      end
    end

    private def resolve_class(decl : AST::ClassDecl)
      saved_tp = @current_type_params
      @current_type_params = decl.type_params
      validate_base_and_interfaces(decl)
      validate_overrides(decl)
      validate_interface_implementations(decl)

      if decl.methods.any? { |m| m.is_synchronized }
        decl.needs_lock_field = true
      end

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

  end
end
