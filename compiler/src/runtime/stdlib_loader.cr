require "../frontend/lexer"
require "../frontend/parser"
require "../semantic/namespace"

module Emerald
  class StdlibLoader
    def self.find_stdlib_path(anchor_file : String? = nil, require_llvm : Bool = false) : String?
      paths = find_stdlib_paths(anchor_file)

      if require_llvm
        llvm_path = paths.find { |path| llvm_stdlib?(path) }
        return llvm_path if llvm_path
      end

      paths.first?
    end

    def self.find_stdlib_paths(anchor_file : String? = nil) : Array(String)
      candidates = [] of String

      if anchor_file
        anchor_dir = File.dirname(File.expand_path(anchor_file))
        add_parent_stdlib_candidates(candidates, anchor_dir)
      end

      add_parent_stdlib_candidates(candidates, Dir.current)

      if executable = Process.executable_path
        bin_dir = File.dirname(executable)

        candidates << File.join(bin_dir, "..", "..", "stdlib")
        candidates << File.join(bin_dir, "..", "stdlib")
        candidates << File.join(bin_dir, "..", "lib", "stdlib")
        candidates << File.join(bin_dir, "..", "..", "lib", "stdlib")
      end

      candidates << "./stdlib"
      candidates << "../stdlib"
      candidates << "../../stdlib"
      candidates << "../../../stdlib"

      if env_path = ENV["EMERALD_STDLIB"]?
        candidates << env_path
      end

      paths = [] of String
      seen = Set(String).new

      candidates.each do |candidate|
        expanded = File.expand_path(candidate)
        normalized = normalize_path(expanded)
        next unless Dir.exists?(expanded)
        next if seen.includes?(normalized)

        paths << expanded
        seen << normalized
      end

      paths
    end

    def self.load_into(program : AST::Program, anchor_file : String? = nil)
      require_llvm = uses_llvm?(program)
      path = find_stdlib_path(anchor_file, require_llvm)
      return unless path

      Dir.glob(File.join(path, "**", "*.ems")).sort.each do |file|
        source = File.read(file)
        tokens = Lexer.new(source).tokenize
        parser = Parser.new(tokens)
        sub_program = parser.parse
        ns = derive_namespace(file, path, sub_program)

        sub_program.declarations.each do |decl|
          case decl
          when AST::ClassDecl
            decl.namespace = ns
          when AST::InterfaceDecl
            decl.namespace = ns
          when AST::FunctionDecl
            decl.namespace = ns
          end

          program.declarations << decl
        end
      end
    end

    private def self.add_parent_stdlib_candidates(candidates : Array(String), start_dir : String)
      dir = File.expand_path(start_dir)

      loop do
        candidates << File.join(dir, "stdlib")

        parent = File.dirname(dir)
        break if parent == dir

        dir = parent
      end
    end

    private def self.uses_llvm?(program : AST::Program) : Bool
      program.declarations.any? do |decl|
        case decl
        when AST::AliasDecl
          decl.target.to_s.starts_with?("Std::Llvm::")
        else
          false
        end
      end
    end

    private def self.llvm_stdlib?(path : String) : Bool
      File.exists?(File.join(path, "llvm", "LlvmContext.ems")) &&
        File.exists?(File.join(path, "llvm", "LlvmNative.ems"))
    end

    private def self.derive_namespace(file_path : String, root : String, ast : AST::Program) : String
      if decl = ast.namespace_decl
        return decl.to_s
      end

      abs_file = normalize_path(File.expand_path(file_path))
      abs_root = normalize_path(File.expand_path(root))
      relative = abs_file.starts_with?(abs_root) ? abs_file[(abs_root.size + 1)..]? : nil
      return DEFAULT_ROOT_NAMESPACE if relative.nil? || relative.empty?

      dir_part = File.dirname(relative)
      return DEFAULT_ROOT_NAMESPACE if dir_part == "." || dir_part.empty?

      segments = dir_part.split("/").reject(&.empty?)
      return DEFAULT_ROOT_NAMESPACE if segments.empty?

      "#{DEFAULT_ROOT_NAMESPACE}::#{segments.map(&.camelcase).join("::")}"
    end

    private def self.normalize_path(path : String) : String
      normalized = path.gsub("\\", "/")
      return normalized.downcase if windows?

      normalized
    end

    private def self.windows? : Bool
      {% if flag?(:windows) %}
        true
      {% else %}
        false
      {% end %}
    end
  end
end
