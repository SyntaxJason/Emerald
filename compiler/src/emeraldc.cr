require "./driver"

module Emerald
  class CLI
    def self.run(args : Array(String))
      if args.empty?
        print_usage
        exit 1
      end

      command = args[0]
      case command
      when "build"
        cmd_build(args[1..])
      when "run"
        cmd_run(args[1..])
      when "check"
        cmd_check(args[1..])
      when "version", "--version", "-v"
        puts "Emerald compiler 0.4.0 (Sprint 4)"
      when "help", "--help", "-h"
        print_usage
      else
        STDERR.puts "Unknown command: #{command}"
        print_usage
        exit 1
      end
    end

    private def self.cmd_build(args : Array(String))
      input, output, _program_args = parse_compile_args(args)
      source_file = require_input(input)

      success = Driver.compile(source_file, output)
      exit 1 unless success
    end

    private def self.cmd_run(args : Array(String))
      input, output, program_args = parse_compile_args(args, true)
      source_file = require_input(input)

      success = Driver.compile(source_file, output)
      exit 1 unless success

      result = Process.run(run_output_path(output), program_args, input: STDIN, output: STDOUT, error: STDERR)
      exit result.exit_code
    end

    private def self.cmd_check(args : Array(String))
      input, report_file = parse_check_args(args)
      source_file = require_input(input)

      success = Driver.check(source_file, report_file)
      exit 1 unless success
    end

    private def self.run_output_path(output : String) : String
      return File.expand_path(output) if File.exists?(output)

      windows_output = "#{output}.exe"
      return File.expand_path(windows_output) if File.exists?(windows_output)

      File.expand_path(output)
    end

    private def self.parse_compile_args(args : Array(String), allow_program_args : Bool = false)
      input : String? = nil
      output = "a.out"
      program_args = [] of String

      i = 0
      while i < args.size
        arg = args[i]

        if allow_program_args && arg == "--"
          program_args = args[(i + 1)...args.size] if i + 1 < args.size
          break
        end

        case arg
        when "-o", "--output"
          i += 1
          if i >= args.size
            STDERR.puts "Error: missing value for #{arg}"
            exit 1
          end
          output = args[i]
        else
          if input
            STDERR.puts "Error: unexpected argument: #{arg}"
            exit 1
          end
          input = arg
        end

        i += 1
      end

      {input, output, program_args}
    end

    private def self.parse_check_args(args : Array(String))
      input : String? = nil
      report_file : String? = nil

      i = 0
      while i < args.size
        arg = args[i]

        case arg
        when "-o", "--output"
          i += 1
          if i >= args.size
            STDERR.puts "Error: missing value for #{arg}"
            exit 1
          end
          report_file = args[i]
        else
          if input
            STDERR.puts "Error: unexpected argument: #{arg}"
            exit 1
          end
          input = arg
        end

        i += 1
      end

      {input, report_file}
    end

    private def self.require_input(input : String?) : String
      unless input
        STDERR.puts "Error: no input file"
        exit 1
      end

      unless File.exists?(input)
        STDERR.puts "Error: file not found: #{input}"
        exit 1
      end

      input
    end

    private def self.print_usage
      puts <<-USAGE
      Usage:
        emeraldc build <file.ems> [-o output]
        emeraldc run <file.ems> [-o output] [-- args...]
        emeraldc check <file.ems> [-o report]
        emeraldc version
        emeraldc help
      USAGE
    end
  end
end

Emerald::CLI.run(ARGV)
