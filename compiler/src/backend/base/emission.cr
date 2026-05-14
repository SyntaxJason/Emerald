require "../base"

module Emerald
  class Codegen
    private def emit_interfaces(io : IO)
      @program.declarations.each do |d|
        emit_interface(io, d.as(AST::InterfaceDecl)) if d.is_a?(AST::InterfaceDecl)
      end
    end

    private def emit_classes(io : IO)
      emitted = Set(String).new
      @program.declarations.each do |d|
        emit_class_recursive(io, d, emitted) if d.is_a?(AST::ClassDecl)
      end
    end

    private def emit_functions(io : IO)
      @program.declarations.each do |d|
        emit_function(io, d.as(AST::FunctionDecl)) if d.is_a?(AST::FunctionDecl)
      end
    end

    private def emit_top_level_then_main(io : IO)
      main_decl : AST::MainDecl? = nil
      @program.declarations.each do |d|
        if d.is_a?(AST::MainDecl)
          main_decl = d.as(AST::MainDecl)
        elsif !d.is_a?(AST::FunctionDecl) && !d.is_a?(AST::ClassDecl) &&
              !d.is_a?(AST::InterfaceDecl) && !d.is_a?(AST::AliasDecl) &&
              !d.is_a?(AST::MacroDecl)
          emit_stmt(io, d)
        end
      end
      if md = main_decl
        md.body.statements.each { |s| emit_stmt(io, s) }
      end
    end

    private def emit_class_recursive(io : IO, decl : AST::ClassDecl, emitted : Set(String))
      class_fqn = "#{decl.namespace}::#{decl.name}"
      return if emitted.includes?(class_fqn)
      if base = decl.base
        @program.declarations.each do |d|
          if d.is_a?(AST::ClassDecl)
            other = d.as(AST::ClassDecl)
            other_fqn = "#{other.namespace}::#{other.name}"
            if other.name == base || other_fqn == base
              emit_class_recursive(io, other, emitted)
            end
          end
        end
      end
      emit_class(io, decl)
      emitted << class_fqn
    end

  end
end
