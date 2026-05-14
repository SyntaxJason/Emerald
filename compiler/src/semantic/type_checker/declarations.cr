require "../type_checker"

module Emerald
  class TypeChecker
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

      ensure_explicit_return(fn.body, ret, "Function '#{fn.name}'", fn.line, fn.col)
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
        method_ret = type_ref_to_fqn(m.return_type)

        saved_ret = @current_function_return
        @current_function_return = method_ret
        check_block(body, m_scope)
        @current_function_return = saved_ret

        ensure_explicit_return(body, method_ret, "Method '#{m.name}'", m.line, m.col)
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
        method_ret = type_ref_to_fqn(m.return_type)

        saved_ret = @current_function_return
        @current_function_return = method_ret
        check_block(body, m_scope)
        @current_function_return = saved_ret

        ensure_explicit_return(body, method_ret, "Method '#{m.name}'", m.line, m.col)

        @current_class = saved
      end
    end

  end
end
