require "../type_checker"

module Emerald
  class TypeChecker
    private def base_type_and_subs(type : String) : Tuple(String, Hash(String, String))
      subs = {} of String => String
      return {type, subs} unless type.includes?("<")

      gen_open = type.index("<").not_nil!
      base_name = type[0...gen_open]
      args_str = type[(gen_open + 1)..-2]
      args = split_top_level(args_str)

      info = @resolver.registry[base_name]
      return {type, subs} unless info
      info.type_params.each_with_index do |param, i|
        subs[param] = args[i]? || "?"
      end
      {base_name, subs}
    end

    private def split_top_level(s : String) : Array(String)
      result = [] of String
      depth = 0
      current = String.build do |sb|
      end
      buf = ""
      s.each_char do |c|
        case c
        when '<' then depth += 1; buf += c.to_s
        when '>' then depth -= 1; buf += c.to_s
        when ','
          if depth == 0
            result << buf.strip
            buf = ""
          else
            buf += c.to_s
          end
        else
          buf += c.to_s
        end
      end
      result << buf.strip unless buf.empty?
      result
    end

    private def apply_subs(type : String, subs : Hash(String, String)) : String
      return type if subs.empty?
      result = type
      subs.each do |k, v|
        result = substitute_type_var(result, k, v)
      end
      result
    end

    private def substitute_type_var(type : String, var : String, replacement : String) : String
      result = ""
      i = 0
      while i < type.size
        if i + var.size <= type.size && type[i, var.size] == var
          before_ok = i == 0 || !alphanum_or_under?(type[i - 1])
          after_ok = i + var.size == type.size || !alphanum_or_under?(type[i + var.size])
          if before_ok && after_ok
            result += replacement
            i += var.size
            next
          end
        end
        result += type[i].to_s
        i += 1
      end
      result
    end

    private def alphanum_or_under?(c : Char) : Bool
      c.ascii_alphanumeric? || c == '_'
    end

  end
end
