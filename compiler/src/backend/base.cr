require "../frontend/ast"
require "../semantic/resolver"
require "./runtime_prelude"
require "../runtime_intrinsics"

module Emerald
  class Codegen
    @match_tmp_counter : Int32
    @typed_local_names : Set(String)

    def initialize(@program : AST::Program, @resolver : Resolver)
      @indent = 0
      @registry = @resolver.registry
      @match_var_counter = 0
      @match_tmp_counter = 0
      @sam_lambda_counter = 0
      @sam_lambda_adapters = [] of AST::LambdaExpr
      @in_captured_block = false
      @typed_local_names = Set(String).new
    end


    def generate : String
      prepare_sam_lambdas(@program)
      String.build do |io|
        RuntimePrelude.emit(io, uses_llvm_runtime?)
        emit_interfaces(io)
        emit_sam_lambda_adapters(io)
        emit_classes(io)
        emit_functions(io)
        emit_top_level_then_main(io)
      end
    end


    private def uses_llvm_runtime? : Bool
      @program.declarations.any? do |decl|
        case decl
        when AST::AliasDecl
          decl.target.to_s.starts_with?("Std::Llvm")
        when AST::ClassDecl
          decl.namespace.starts_with?("Std::Llvm")
        when AST::InterfaceDecl
          decl.namespace.starts_with?("Std::Llvm")
        when AST::FunctionDecl
          decl.namespace.starts_with?("Std::Llvm")
        else
          false
        end
      end
    end


    def fresh_match_var : String
      @match_var_counter += 1
      "__m#{@match_var_counter}"
    end


    def indent(io : IO)
      @indent.times { io << "  " }
    end


    private def reset_typed_locals
      @typed_local_names = Set(String).new
    end


    private def register_typed_local(name : String)
      @typed_local_names << crystal_local_name(name)
    end


    private def needs_typed_local_annotation?(name : String) : Bool
      local_name = crystal_local_name(name)

      return false if @typed_local_names.includes?(local_name)

      @typed_local_names << local_name
      true
    end


  end
end

require "./base/types"
require "./base/escaping"
require "./base/emission"
