module Emerald
  module DiagnosticRenderer
    extend self

    FUN_ERROR_LINES = [
      "Emerald tripped over the code. The floor is under investigation.",
      "Something went sideways. At least it did so with confidence.",
      "Emerald looked at the code and quietly whispered: bruh.",
      "Small compiler accident. Only the pride was injured.",
      "The code tried to turn left, but syntax forgot the steering wheel.",
      "Emerald found a red flag. Sadly, not the decorative kind.",
      "This was almost correct. From a very generous distance.",
      "The compiler tried to stay polite. It did its best.",
      "Something exploded. In a controlled and educational way.",
      "Emerald lost the plot here. Probably somewhere near this column.",
      "The code attempted a backflip and landed on the TypeChecker.",
      "This looks like a classic 'not like that, boss' moment.",
      "Emerald is not angry. Just compile-time disappointed.",
      "There is an error here. It looks peaceful, but it is still wrong.",
      "The compiler said no. Firmly, but with character.",
      "The program wanted to live. The TypeChecker had other plans.",
      "A tiny thing is broken. Tiny in the disaster-movie sense.",
      "Emerald caught this error before it could grow up.",
      "A bug tried to disguise itself as a feature. Poor costume choice.",
      "The code is not dead. It is just not compiling right now.",
      "Not much is missing. Only the part that mattered.",
      "The compiler restored a safe distance from reality.",
      "That was brave. Unfortunately, bravery is not valid syntax.",
      "Emerald reports: creative idea, technical rejection.",
      "Something went off track. The track was strongly typed.",
      "This error is fresh, local, and handcrafted.",
      "Compiler says no. But with personality.",
      "This is not a bug. It is a very loud hint.",
      "Emerald blinked once. The error was still there.",
      "The code had different plans than the compiler today."
    ] of String

    def render(io : IO, source_file : String, label : String, message : String, line : Int32, col : Int32, hint : String? = nil, length : Int32 = 1)
      clean_message = strip_location_suffix(message)

      print_fun_error_line(io)

      io.puts "#{source_file}:#{line}:#{col}"
      io.puts "#{label}: #{clean_message}"

      if source = read_source_line(source_file, line)
        io.puts
        io.puts "    #{source.rstrip}"
        io.puts "    #{marker(col, length)}"
      end

      if hint_value = hint
        io.puts
        io.puts "hint: #{hint_value}"
      end
    end

    private def print_fun_error_line(io : IO)
      return if ENV["EMERALD_PLAIN_ERRORS"]? == "1"

      index = rand(FUN_ERROR_LINES.size)
      io.puts FUN_ERROR_LINES[index]
      io.puts
    end

    private def strip_location_suffix(message : String) : String
      message.gsub(/ at \d+:\d+$/, "")
    end

    private def read_source_line(source_file : String, line : Int32) : String?
      return nil unless File.exists?(source_file)
      return nil if line <= 0

      lines = File.read_lines(source_file)
      return nil if line > lines.size

      lines[line - 1]
    rescue
      nil
    end

    private def marker(col : Int32, length : Int32) : String
      safe_col = col <= 0 ? 1 : col
      safe_length = length <= 0 ? 1 : length

      "#{" " * (safe_col - 1)}#{"^" * safe_length}"
    end
  end
end
