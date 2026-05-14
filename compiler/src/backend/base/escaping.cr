require "../base"

module Emerald
  class Codegen
    def escape_for_dq(s : String) : String
      s.gsub('\\', "\\\\")
       .gsub('"', "\\\"")
       .gsub('#', "\\#")
       .gsub('\n', "\\n")
       .gsub('\t', "\\t")
       .gsub('\r', "\\r")
    end

    def escape_char(s : String) : String
      case s
      when "\n" then "\\n"
      when "\t" then "\\t"
      when "\r" then "\\r"
      when "\\" then "\\\\"
      when "'"  then "\\'"
      when "\0" then "\\0"
      else s
      end
    end

  end
end
