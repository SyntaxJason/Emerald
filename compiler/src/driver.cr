require "./frontend/lexer"
require "./frontend/parser"
require "./semantic/resolver"
require "./semantic/type_checker"
require "./backend/codegen"
require "./runtime/stdlib_loader"
require "./runtime/project_loader"

module Emerald
  class Driver
    def self.compile(source_file : String, output : String) : Bool
      begin
        program = ProjectLoader.load(source_file)

        resolver = Resolver.new
        resolver.resolve(program)

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
        STDERR.puts "Error: #{ex.message}"
        false
      rescue ex : ParseError
        STDERR.puts "Error: #{ex.message}"
        false
      rescue ex : ResolveError
        STDERR.puts "Error: #{ex.message}"
        false
      rescue ex : TypeError
        STDERR.puts "Error: #{ex.message}"
        false
      end
    end
  end
end
