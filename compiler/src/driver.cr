require "./frontend/lexer"
require "./frontend/parser"
require "./semantic/resolver"
require "./semantic/type_checker"
require "./backend/codegen"
require "./runtime/stdlib_loader"
require "./runtime/project_loader"
require "./macro_engine/expander"
require "./diagnostics"

module Emerald
  class Driver
    def self.compile(source_file : String, output : String) : Bool
      begin
        program = ProjectLoader.load(source_file)
        StdlibLoader.load_into(program)

        resolver = Resolver.new
        resolver.resolve(program)

        expander = MacroEngine::MacroExpander.new
        expander.expand(program, resolver)

        unless program.macro_registry.macros.empty?
          resolver = Resolver.new
          resolver.resolve(program)
        end

        checker = TypeChecker.new(resolver)
        checker.check(program)

        crystal_code = Codegen.new(program, resolver).generate

        Dir.mkdir_p(File.dirname(output)) unless File.dirname(output) == "."

        tmpdir = File.tempname("emeraldc-build")
        Dir.mkdir_p(tmpdir)
        cr_file = File.join(tmpdir, "main.cr")
        File.write(cr_file, crystal_code)

        result = Process.run("crystal", ["build", cr_file, "-o", output],
                             output: STDOUT, error: STDERR)
        unless result.success?
          STDERR.puts "Compilation failed: Crystal compilation failed (exit #{result.exit_code})"
          return false
        end

        puts "Built: #{output}"
        true
      rescue ex : LexError
        DiagnosticRenderer.render(STDERR, source_file, "error", ex.message || "lexer error", ex.line, ex.col)
        false
      rescue ex : ParseError
        DiagnosticRenderer.render(STDERR, source_file, "error", ex.message || "parse error", ex.line, ex.col)
        false
      rescue ex : ResolveError
        DiagnosticRenderer.render(STDERR, source_file, "error", ex.message || "resolve error", ex.line, ex.col)
        false
      rescue ex : TypeError
        DiagnosticRenderer.render(STDERR, source_file, "error", ex.message || "type error", ex.line, ex.col, ex.hint, ex.length)
        false
      end
    end
  end
end
