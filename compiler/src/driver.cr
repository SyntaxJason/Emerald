require "json"
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
        program = checked_program(source_file)

        crystal_code = Codegen.new(program[0], program[1]).generate

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
        render_and_report(source_file, nil, "lex", "lexer error", ex.message, ex.line, ex.col)
        false
      rescue ex : ParseError
        render_and_report(source_file, nil, "parse", "parse error", ex.message, ex.line, ex.col)
        false
      rescue ex : ResolveError
        render_and_report(source_file, nil, "resolve", "resolve error", ex.message, ex.line, ex.col)
        false
      rescue ex : TypeError
        render_and_report(source_file, nil, "type", "type error", ex.message, ex.line, ex.col, ex.hint, ex.length)
        false
      end
    end

    def self.check(source_file : String, report_file : String? = nil) : Bool
      begin
        checked_program(source_file)
        write_check_success(report_file, source_file)
        puts "Checked: #{source_file}"
        true
      rescue ex : LexError
        render_and_report(source_file, report_file, "lex", "lexer error", ex.message, ex.line, ex.col)
        false
      rescue ex : ParseError
        render_and_report(source_file, report_file, "parse", "parse error", ex.message, ex.line, ex.col)
        false
      rescue ex : ResolveError
        render_and_report(source_file, report_file, "resolve", "resolve error", ex.message, ex.line, ex.col)
        false
      rescue ex : TypeError
        render_and_report(source_file, report_file, "type", "type error", ex.message, ex.line, ex.col, ex.hint, ex.length)
        false
      end
    end

    private def self.checked_program(source_file : String)
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

      {program, resolver}
    end

    private def self.render_and_report(source_file : String, report_file : String?, phase : String, fallback : String, message : String?, line : Int32, col : Int32, hint : String? = nil, length : Int32 = 1)
      clean_message = clean_diagnostic_message(message || fallback)
      DiagnosticRenderer.render(STDERR, source_file, "error", clean_message, line, col, hint, length)
      write_check_error(report_file, source_file, phase, clean_message, line, col, hint, length)
    end

    private def self.write_check_success(report_file : String?, source_file : String)
      return unless path = report_file

      dirname = File.dirname(path)
      Dir.mkdir_p(dirname) unless dirname == "."

      File.write(path, JSON.build do |json|
        json.object do
          json.field "format", "emerald-check-v1"
          json.field "ok", true
          json.field "source", File.expand_path(source_file)
          json.field "diagnostics" do
            json.array do
            end
          end
        end
      end)
    end

    private def self.write_check_error(report_file : String?, source_file : String, phase : String, message : String, line : Int32, col : Int32, hint : String?, length : Int32)
      return unless path = report_file

      dirname = File.dirname(path)
      Dir.mkdir_p(dirname) unless dirname == "."

      File.write(path, JSON.build do |json|
        json.object do
          json.field "format", "emerald-check-v1"
          json.field "ok", false
          json.field "source", File.expand_path(source_file)
          json.field "diagnostics" do
            json.array do
              json.object do
                json.field "severity", "error"
                json.field "file", File.expand_path(source_file)
                json.field "phase", phase
                json.field "message", message
                json.field "line", line
                json.field "column", col
                json.field "lineBase", 1
                json.field "columnBase", 1
                json.field "length", length
                json.field "hint", hint
                json.field "sourceLine", source_line(source_file, line)
              end
            end
          end
        end
      end)
    end

    private def self.clean_diagnostic_message(message : String) : String
      message.gsub(/ at \d+:\d+$/, "")
    end

    private def self.source_line(source_file : String, line : Int32) : String?
      return nil unless File.exists?(source_file)
      return nil if line <= 0

      lines = File.read_lines(source_file)
      return nil if line > lines.size

      lines[line - 1]
    rescue
      nil
    end
  end
end
