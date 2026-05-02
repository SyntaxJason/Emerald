require "../frontend/lexer"
require "../frontend/parser"
require "../semantic/namespace"

module Emerald
  class StdlibLoader
    def self.find_stdlib_path : String?
      if env_path = ENV["EMERALD_STDLIB"]?
        return env_path if Dir.exists?(env_path)
      end
      bin_dir = File.dirname(Process.executable_path || "")
      candidate = File.expand_path(File.join(bin_dir, "..", "lib", "stdlib"))
      return candidate if Dir.exists?(candidate)
      ["./stdlib", "../stdlib", "../../stdlib"].each do |rel|
        path = File.expand_path(rel)
        return path if Dir.exists?(path)
      end
      nil
    end

    def self.load_into(program : AST::Program)
      path = find_stdlib_path
      return unless path

      Dir.glob(File.join(path, "**", "*.ems")).each do |file|
        source = File.read(file)
        tokens = Lexer.new(source).tokenize
        parser = Parser.new(tokens)
        sub_program = parser.parse
        ns = derive_namespace(file, path, sub_program)
        sub_program.declarations.each do |decl|
          case decl
          when AST::ClassDecl     then decl.namespace = ns
          when AST::InterfaceDecl then decl.namespace = ns
          when AST::FunctionDecl  then decl.namespace = ns
          end
          program.declarations << decl
        end
      end
    end

    private def self.derive_namespace(file_path : String, root : String, ast : AST::Program) : String
      if decl = ast.namespace_decl
        return decl.to_s
      end
      abs_file = File.expand_path(file_path)
      abs_root = File.expand_path(root)
      relative = abs_file.starts_with?(abs_root) ? abs_file[(abs_root.size + 1)..]? : nil
      return DEFAULT_ROOT_NAMESPACE if relative.nil? || relative.empty?
      dir_part = File.dirname(relative)
      return DEFAULT_ROOT_NAMESPACE if dir_part == "." || dir_part.empty?
      segments = dir_part.split("/").reject(&.empty?)
      return DEFAULT_ROOT_NAMESPACE if segments.empty?
      "#{DEFAULT_ROOT_NAMESPACE}::#{segments.join("::")}"
    end
  end
end
