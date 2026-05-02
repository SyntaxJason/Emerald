require "../frontend/lexer"
require "../frontend/parser"
require "../semantic/namespace"

module Emerald
  class ProjectLoader
    def self.load(entry_file : String) : AST::Program
      entry_path = File.expand_path(entry_file)
      project_root = find_project_root(entry_path)

      merged = AST::Program.new

      entry_source = File.read(entry_path)
      entry_tokens = Lexer.new(entry_source).tokenize
      entry_parser = Parser.new(entry_tokens)
      entry_ast = entry_parser.parse
      entry_ast.source_path = entry_path
      entry_ns = derive_namespace(entry_path, project_root, entry_ast)
      merged.namespace_decl = entry_ast.namespace_decl
      apply_namespace_to_decls(entry_ast, entry_ns)
      entry_ast.declarations.each { |d| merged.declarations << d }

      if project_root && in_project?(entry_path, project_root)
        Dir.glob(File.join(project_root, "**", "*.ems")).each do |file|
          next if File.expand_path(file) == entry_path
          source = File.read(file)
          tokens = Lexer.new(source).tokenize
          parser = Parser.new(tokens)
          sub_ast = parser.parse
          sub_ast.source_path = file
          sub_ns = derive_namespace(file, project_root, sub_ast)
          apply_namespace_to_decls(sub_ast, sub_ns)
          sub_ast.declarations.each { |d| merged.declarations << d }
        end
      end

      merged
    end

    private def self.in_project?(entry_path : String, project_root : String) : Bool
      File.expand_path(entry_path).starts_with?(File.expand_path(project_root))
    end

    private def self.find_project_root(entry_path : String) : String?
      dir = File.dirname(entry_path)
      while dir.size > 1
        src_dir = File.join(dir, "src")
        if Dir.exists?(src_dir) && File.expand_path(entry_path).starts_with?(File.expand_path(src_dir))
          return src_dir
        end
        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end
      nil
    end

    private def self.derive_namespace(file_path : String, project_root : String?, ast : AST::Program) : String
      if decl = ast.namespace_decl
        return decl.to_s
      end

      return DEFAULT_ROOT_NAMESPACE unless project_root

      abs_file = File.expand_path(file_path)
      abs_root = File.expand_path(project_root)
      relative = abs_file.starts_with?(abs_root) ? abs_file[(abs_root.size + 1)..]? : nil
      return DEFAULT_ROOT_NAMESPACE if relative.nil? || relative.empty?

      dir_part = File.dirname(relative)
      return DEFAULT_ROOT_NAMESPACE if dir_part == "." || dir_part.empty?

      segments = dir_part.split("/").reject(&.empty?)
      return DEFAULT_ROOT_NAMESPACE if segments.empty?

      "#{DEFAULT_ROOT_NAMESPACE}::#{segments.join("::")}"
    end

    private def self.apply_namespace_to_decls(ast : AST::Program, ns : String)
      ast.declarations.each do |d|
        case d
        when AST::ClassDecl     then d.namespace = ns
        when AST::InterfaceDecl then d.namespace = ns
        when AST::FunctionDecl  then d.namespace = ns
        end
      end
    end
  end
end
