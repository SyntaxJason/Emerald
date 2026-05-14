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
    property program : AST::Program?

    def initialize
      @global_scope = Scope.new
      @registry = ClassRegistry.new
      @namespace_resolver = NamespaceResolver.new(@registry)
      @current_namespace = ""
      @current_type_params = [] of String
      @program = nil
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

      ["Fiber", "Thread", "VirtualThread", "Channel", "Console", "Math"].each do |name|
        @global_scope.declare(name, TypeSymbol.new(name, "builtin", name), 0, 0)
      end
      @global_scope.declare("Mutex", TypeSymbol.new("Mutex", "builtin", "Mutex"), 0, 0)

      MACRO_AST_TYPES.each do |name|
        @global_scope.declare(name, TypeSymbol.new(name, "builtin", name), 0, 0)
      end
    end


    def resolve(program : AST::Program)
      @program = program
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


    BUILTIN_ANNOTATION_NAMES = ["Override", "override", "Async", "Synchronized", "Deprecated"]
    MACRO_BUILDER_NAMES = ["Stmt", "Expr", "Block", "MethodAST", "ClassAST", "FieldAST", "ParamAST"]

  end
end

require "./resolver/declarations"
require "./resolver/members"
require "./resolver/classes"
require "./resolver/validation"
require "./resolver/statements"
require "./resolver/expressions"
