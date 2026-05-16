require "../frontend/ast"
require "../semantic/resolver"
require "./runtime_prelude"
require "../runtime_intrinsics"

module Emerald
  class Codegen
    @match_tmp_counter : Int32

    def initialize(@program : AST::Program, @resolver : Resolver)
      @indent = 0
      @registry = @resolver.registry
      @match_var_counter = 0
      @match_tmp_counter = 0
      @sam_lambda_counter = 0
      @sam_lambda_adapters = [] of AST::LambdaExpr
      @in_captured_block = false
    end


    def generate : String
      prepare_sam_lambdas(@program)
      String.build do |io|
        RuntimePrelude.emit(io)
        emit_interfaces(io)
        emit_sam_lambda_adapters(io)
        emit_classes(io)
        emit_functions(io)
        emit_top_level_then_main(io)
      end
    end


    def fresh_match_var : String
      @match_var_counter += 1
      "__m#{@match_var_counter}"
    end


    def indent(io : IO)
      @indent.times { io << "  " }
    end


  end
end

require "./base/types"
require "./base/escaping"
require "./base/emission"
