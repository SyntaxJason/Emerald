require "../frontend/ast"
require "./resolver"
require "./type_system"
require "./builtin_methods"

module Emerald
  class TypeError < Exception
    getter line : Int32
    getter col : Int32
    getter hint : String?
    getter length : Int32

    def initialize(message : String, @line : Int32, @col : Int32, @hint : String? = nil, @length : Int32 = 1)
      super(message)
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


  end
end

require "./type_checker/declarations"
require "./type_checker/returns"
require "./type_checker/statements"
require "./type_checker/expressions"
require "./type_checker/calls"
require "./type_checker/generics"
require "./type_checker/members"
require "./type_checker/lambdas"
require "./type_checker/match"
require "./type_checker/helpers"
