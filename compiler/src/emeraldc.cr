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
      input : String? = nil
      output = "a.out"
      i = 0
      while i < args.size
        case args[i]
        when "-o"
          i += 1
          output = args[i]
        else
          input = args[i]
        end
        i += 1
      end

      unless input
        STDERR.puts "Error: no input file"
        exit 1
      end
      unless File.exists?(input)
        STDERR.puts "Error: file not found: #{input}"
        exit 1
      end

      success = Driver.compile(input, output)
      exit 1 unless success
    end

    private def self.print_usage
      puts <<-USAGE
      Usage:
        emeraldc build <file.ems> [-o output]
        emeraldc version
        emeraldc help
      USAGE
    end
  end
end

Emerald::CLI.run(ARGV)
