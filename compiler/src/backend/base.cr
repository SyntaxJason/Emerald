require "../frontend/ast"
require "../semantic/resolver"
require "../semantic/builtin_methods"
require "./runtime_prelude"

module Emerald
  class Codegen
    def initialize(@program : AST::Program, @resolver : Resolver)
      @indent = 0
      @registry = @resolver.registry
      @match_var_counter = 0
    end

    def generate : String
      String.build do |io|
        RuntimePrelude.emit(io)
        emit_interfaces(io)
        emit_classes(io)
        emit_functions(io)
        emit_top_level_then_main(io)
      end
    end

    def fresh_match_var : String
      @match_var_counter += 1
      "__m#{@match_var_counter}"
    end

    def crystal_type(t : String) : String
      case t
      when "Int"    then "Int64"
      when "Float"  then "Float64"
      when "Bool"   then "Bool"
      when "Char"   then "Char"
      when "String" then "String"
      when "Void"   then "Nil"
      when "Any"    then "Object"
      else
        if t.starts_with?("Result<")
          "EmeraldResult"
        elsif t.starts_with?("List<")
          inner = BuiltinMethods.extract_type_arg(t)
          "Array(#{crystal_type(inner)})"
        elsif t.starts_with?("Map<")
          k, v = BuiltinMethods.extract_type_args2(t)
          "Hash(#{crystal_type(k)}, #{crystal_type(v)})"
        elsif t.starts_with?("Set<")
          inner = BuiltinMethods.extract_type_arg(t)
          "Set(#{crystal_type(inner)})"
        elsif t.starts_with?("Fiber<")
          inner = t[(t.index("<").not_nil! + 1)..-2]
          "EmeraldFiber(#{crystal_type(inner)})"
        elsif t.starts_with?("VirtualThread<")
          inner = t[(t.index("<").not_nil! + 1)..-2]
          "EmeraldFiber(#{crystal_type(inner)})"
        elsif t.starts_with?("Thread<")
          inner = t[(t.index("<").not_nil! + 1)..-2]
          "EmeraldThread(#{crystal_type(inner)})"
        elsif t.starts_with?("Channel<")
          inner = t[(t.index("<").not_nil! + 1)..-2]
          "Channel(#{crystal_type(inner)})"
        elsif t == "Mutex"
          "Mutex"
        elsif t.starts_with?("Fn(")
          inner = t[3..-1]
          colon_idx = inner.rindex("):") || inner.size
          params_part = inner[0...colon_idx]
          ret_part = colon_idx < inner.size ? inner[(colon_idx + 2)..] : "Nil"
          params = params_part.empty? ? [] of String : params_part.split(",")
          crystal_params = params.map { |p| crystal_type(p.strip) }
          ret_crystal = crystal_type(ret_part.strip)
          if crystal_params.empty?
            "Proc(#{ret_crystal})"
          else
            "Proc(#{crystal_params.join(", ")}, #{ret_crystal})"
          end
        elsif t.includes?("<") && t.ends_with?(">")
          gen_open = t.index("<").not_nil!
          base = t[0...gen_open]
          args_str = t[(gen_open + 1)..-2]
          args = split_top_level_args(args_str)
          crystal_args = args.map { |a| crystal_type(a.strip) }
          "#{mangle_fqn(base)}(#{crystal_args.join(", ")})"
        else
          mangle_fqn(t)
        end
      end
    end

    private def split_top_level_args(s : String) : Array(String)
      result = [] of String
      depth = 0
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

    def mangle_fqn(fqn : String) : String
      fqn.gsub("::", "_")
    end

    def type_ref_name(ref : AST::TypeRef) : String
      case ref
      when AST::NamedType
        ref.as(AST::NamedType).name
      when AST::FunctionType
        ft = ref.as(AST::FunctionType)
        params = ft.param_types.map { |p| type_ref_name(p) }.join(",")
        "Fn(#{params}):#{type_ref_name(ft.return_type)}"
      when AST::GenericType
        gt = ref.as(AST::GenericType)
        args = gt.type_args.map { |a| type_ref_name(a) }.join(",")
        "#{gt.name}<#{args}>"
      else
        "Unknown"
      end
    end

    def indent(io : IO)
      @indent.times { io << "  " }
    end

    def escape_for_dq(s : String) : String
      s.gsub('\\', "\\\\")
       .gsub('"', "\\\"")
       .gsub('#', "\\#")
       .gsub('\n', "\\n")
       .gsub('\t', "\\t")
       .gsub('\r', "\\r")
    end

    def escape_char(s : String) : String
      case s
      when "\n" then "\\n"
      when "\t" then "\\t"
      when "\r" then "\\r"
      when "\\" then "\\\\"
      when "'"  then "\\'"
      when "\0" then "\\0"
      else s
      end
    end

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
              !d.is_a?(AST::InterfaceDecl) && !d.is_a?(AST::AliasDecl)
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
