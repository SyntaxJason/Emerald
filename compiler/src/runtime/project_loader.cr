require "../frontend/lexer"
require "../frontend/parser"
require "../semantic/namespace"

module Emerald
  class ProjectLoader
    def self.load(entry_file : String) : AST::Program
      entry_path = File.expand_path(entry_file)
      project_root = find_project_root(entry_path)

      merged = AST::Program.new

      source_files = files_for(entry_path, project_root)
      source_files.each do |file|
        ast = parse_file(file)
        ns = derive_namespace(file, project_root, ast)

        merged.namespace_decl = ast.namespace_decl if file == entry_path
        apply_namespace_to_decls(ast, ns)
        ast.declarations.each { |d| merged.declarations << d }
      end

      merged
    end

    private def self.files_for(entry_path : String, project_root : String?) : Array(String)
      return [entry_path] unless project_root && in_project?(entry_path, project_root)

      files = Dir.glob(File.join(project_root, "**", "*.ems")).map { |file| File.expand_path(file) }.sort
      files = files.reject { |file| file == entry_path }
      files << entry_path

      files
    end

    private def self.parse_file(file : String) : AST::Program
      source = File.read(file)
      tokens = Lexer.new(source).tokenize
      parser = Parser.new(tokens)
      ast = parser.parse
      ast.source_path = file

      ast
    end

    private def self.in_project?(entry_path : String, project_root : String) : Bool
      File.expand_path(entry_path).starts_with?(File.expand_path(project_root))
    end

    private def self.find_project_root(entry_path : String) : String?
      if env_root = ENV["EMERALD_PROJECT_ROOT"]?
        expanded = File.expand_path(env_root)
        return expanded if Dir.exists?(expanded)
      end

      dir = File.dirname(entry_path)
      while dir.size > 1
        src_dir = File.join(dir, "src")
        if Dir.exists?(src_dir) && File.expand_path(entry_path).starts_with?(File.expand_path(src_dir))
          return src_dir
        end

        [".emerald-studio", ".emerald", "emerald.json"].each do |marker|
          marker_path = File.join(dir, marker)
          return dir if Dir.exists?(marker_path) || File.exists?(marker_path)
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
