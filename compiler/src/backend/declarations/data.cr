require "../declarations"

module Emerald
  class Codegen
    private def emit_data_constructor(io : IO, decl : AST::ClassDecl)
      indent(io); io << "def initialize("
      decl.fields.each_with_index do |f, i|
        io << ", " if i > 0
        io << "@" << f.name << " : " << crystal_type(field_type_fqn(f, decl.namespace))
      end
      io << ")\n"
      indent(io); io << "end\n\n"
    end

    private def emit_data_copy(io : IO, decl : AST::ClassDecl, mangled : String)
      indent(io); io << "def copy("
      decl.fields.each_with_index do |f, i|
        io << ", " if i > 0
        io << f.name << " : " << crystal_type(field_type_fqn(f, decl.namespace)) << "? = nil"
      end
      io << ") : " << mangled << "\n"
      @indent += 1
      indent(io); io << mangled << ".new("
      decl.fields.each_with_index do |f, i|
        io << ", " if i > 0
        io << f.name << " || @" << f.name
      end
      io << ")\n"
      @indent -= 1
      indent(io); io << "end\n\n"
    end

    private def emit_data_equals(io : IO, decl : AST::ClassDecl, mangled : String)
      indent(io); io << "def equals(other : " << mangled << ") : Bool\n"
      @indent += 1
      if decl.fields.empty?
        indent(io); io << "true\n"
      else
        indent(io)
        decl.fields.each_with_index do |f, i|
          io << " && " if i > 0
          io << "@" << f.name << " == other.@" << f.name
        end
        io << "\n"
      end
      @indent -= 1
      indent(io); io << "end\n\n"
    end

    private def emit_data_to_string(io : IO, decl : AST::ClassDecl)
      indent(io); io << "def to_s(io : IO)\n"
      @indent += 1
      indent(io); io << "io << \"" << decl.name << "(\"\n"
      decl.fields.each_with_index do |f, i|
        if i > 0
          indent(io); io << "io << \", \"\n"
        end
        indent(io); io << "io << @" << f.name << "\n"
      end
      indent(io); io << "io << \")\"\n"
      @indent -= 1
      indent(io); io << "end\n\n"
    end

  end
end
