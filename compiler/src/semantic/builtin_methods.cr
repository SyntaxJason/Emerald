module Emerald
  class BuiltinMethod
    getter name : String
    getter param_types : Array(String)
    getter return_type : String
    getter crystal_template : String

    def initialize(@name, @param_types, @return_type, @crystal_template); end
  end

  module BuiltinMethods
    extend self

    @@string_methods : Hash(String, BuiltinMethod)?
    @@int_methods : Hash(String, BuiltinMethod)?
    @@float_methods : Hash(String, BuiltinMethod)?
    @@bool_methods : Hash(String, BuiltinMethod)?
    @@char_methods : Hash(String, BuiltinMethod)?

    def string_methods : Hash(String, BuiltinMethod)
      @@string_methods ||= build_string_methods
    end

    def int_methods : Hash(String, BuiltinMethod)
      @@int_methods ||= build_int_methods
    end

    def float_methods : Hash(String, BuiltinMethod)
      @@float_methods ||= build_float_methods
    end

    def bool_methods : Hash(String, BuiltinMethod)
      @@bool_methods ||= build_bool_methods
    end

    def char_methods : Hash(String, BuiltinMethod)
      @@char_methods ||= build_char_methods
    end

    def for_type(type : String) : Hash(String, BuiltinMethod)?
      case type
      when "String" then string_methods
      when "Int"    then int_methods
      when "Float"  then float_methods
      when "Bool"   then bool_methods
      when "Char"   then char_methods
      else
        if type.starts_with?("List<")
          list_methods(extract_type_arg(type))
        elsif type.starts_with?("Map<")
          map_methods(*extract_type_args2(type))
        elsif type.starts_with?("Set<")
          set_methods(extract_type_arg(type))
        else
          nil
        end
      end
    end

    def is_builtin_container?(type : String) : Bool
      type.starts_with?("List<") || type.starts_with?("Map<") || type.starts_with?("Set<")
    end

    def extract_type_arg(t : String) : String
      open = t.index("<").not_nil!
      inner = t[(open + 1)..-2]
      inner
    end

    def extract_type_args2(t : String) : Tuple(String, String)
      open = t.index("<").not_nil!
      inner = t[(open + 1)..-2]
      depth = 0
      split_idx = -1
      inner.each_char_with_index do |c, i|
        case c
        when '<' then depth += 1
        when '>' then depth -= 1
        when ','
          if depth == 0
            split_idx = i
            break
          end
        end
      end
      if split_idx >= 0
        {inner[0...split_idx].strip, inner[(split_idx + 1)..].strip}
      else
        {inner.strip, "?"}
      end
    end

    private def build_string_methods : Hash(String, BuiltinMethod)
      m = {} of String => BuiltinMethod
      m["length"]      = BuiltinMethod.new("length", [] of String, "Int", "(%recv%).size.to_i64")
      m["isEmpty"]     = BuiltinMethod.new("isEmpty", [] of String, "Bool", "(%recv%).empty?")
      m["charAt"]      = BuiltinMethod.new("charAt", ["Int"], "Char", "(%recv%)[%a0%]")
      m["substring"]   = BuiltinMethod.new("substring", ["Int", "Int"], "String", "(%recv%)[%a0%...%a1%]")
      m["split"]       = BuiltinMethod.new("split", ["String"], "List<String>", "(%recv%).split(%a0%)")
      m["trim"]        = BuiltinMethod.new("trim", [] of String, "String", "(%recv%).strip")
      m["toUpper"]     = BuiltinMethod.new("toUpper", [] of String, "String", "(%recv%).upcase")
      m["toLower"]     = BuiltinMethod.new("toLower", [] of String, "String", "(%recv%).downcase")
      m["contains"]    = BuiltinMethod.new("contains", ["String"], "Bool", "(%recv%).includes?(%a0%)")
      m["startsWith"]  = BuiltinMethod.new("startsWith", ["String"], "Bool", "(%recv%).starts_with?(%a0%)")
      m["endsWith"]    = BuiltinMethod.new("endsWith", ["String"], "Bool", "(%recv%).ends_with?(%a0%)")
      m["replace"]     = BuiltinMethod.new("replace", ["String", "String"], "String", "(%recv%).gsub(%a0%, %a1%)")
      m["indexOf"]     = BuiltinMethod.new("indexOf", ["String"], "Int", "((%recv%).index(%a0%) || -1).to_i64")
      m["toInt"]       = BuiltinMethod.new("toInt", [] of String, "Int", "(%recv%).to_i64")
      m["toFloat"]     = BuiltinMethod.new("toFloat", [] of String, "Float", "(%recv%).to_f64")
      m["repeat"]      = BuiltinMethod.new("repeat", ["Int"], "String", "(%recv%) * %a0%")
      m["reverse"]     = BuiltinMethod.new("reverse", [] of String, "String", "(%recv%).reverse")
      m
    end

    private def build_int_methods : Hash(String, BuiltinMethod)
      m = {} of String => BuiltinMethod
      m["toString"] = BuiltinMethod.new("toString", [] of String, "String", "(%recv%).to_s")
      m["toFloat"]  = BuiltinMethod.new("toFloat", [] of String, "Float", "(%recv%).to_f64")
      m["abs"]      = BuiltinMethod.new("abs", [] of String, "Int", "(%recv%).abs")
      m
    end

    private def build_float_methods : Hash(String, BuiltinMethod)
      m = {} of String => BuiltinMethod
      m["toString"] = BuiltinMethod.new("toString", [] of String, "String", "(%recv%).to_s")
      m["toInt"]    = BuiltinMethod.new("toInt", [] of String, "Int", "(%recv%).to_i64")
      m["abs"]      = BuiltinMethod.new("abs", [] of String, "Float", "(%recv%).abs")
      m["isNaN"]    = BuiltinMethod.new("isNaN", [] of String, "Bool", "(%recv%).nan?")
      m
    end

    private def build_bool_methods : Hash(String, BuiltinMethod)
      m = {} of String => BuiltinMethod
      m["toString"] = BuiltinMethod.new("toString", [] of String, "String", "(%recv%).to_s")
      m
    end

    private def build_char_methods : Hash(String, BuiltinMethod)
      m = {} of String => BuiltinMethod
      m["toString"]     = BuiltinMethod.new("toString", [] of String, "String", "(%recv%).to_s")
      m["isDigit"]      = BuiltinMethod.new("isDigit", [] of String, "Bool", "(%recv%).ascii_number?")
      m["isLetter"]     = BuiltinMethod.new("isLetter", [] of String, "Bool", "(%recv%).ascii_letter?")
      m["isWhitespace"] = BuiltinMethod.new("isWhitespace", [] of String, "Bool", "(%recv%).whitespace?")
      m
    end

    def list_methods(t : String) : Hash(String, BuiltinMethod)
      m = {} of String => BuiltinMethod
      m["length"]    = BuiltinMethod.new("length", [] of String, "Int", "(%recv%).size.to_i64")
      m["isEmpty"]   = BuiltinMethod.new("isEmpty", [] of String, "Bool", "(%recv%).empty?")
      m["get"]       = BuiltinMethod.new("get", ["Int"], t, "(%recv%)[%a0%]")
      m["set"]       = BuiltinMethod.new("set", ["Int", t], "Void", "(%recv%)[%a0%] = %a1%")
      m["add"]       = BuiltinMethod.new("add", [t], "Void", "(%recv%) << %a0%")
      m["addAt"]     = BuiltinMethod.new("addAt", ["Int", t], "Void", "(%recv%).insert(%a0%, %a1%)")
      m["remove"]    = BuiltinMethod.new("remove", [t], "Bool", "((%recv%).delete(%a0%) != nil)")
      m["removeAt"]  = BuiltinMethod.new("removeAt", ["Int"], t, "(%recv%).delete_at(%a0%)")
      m["contains"]  = BuiltinMethod.new("contains", [t], "Bool", "(%recv%).includes?(%a0%)")
      m["indexOf"]   = BuiltinMethod.new("indexOf", [t], "Int", "((%recv%).index(%a0%) || -1).to_i64")
      m["clear"]     = BuiltinMethod.new("clear", [] of String, "Void", "(%recv%).clear")
      m["forEach"]   = BuiltinMethod.new("forEach", ["Fn(#{t}):Void"], "Void", "(%recv%).each { |__e| %a0%.call(__e) }")
      m["map"]       = BuiltinMethod.new("map", ["Fn(#{t}):?"], "List<?>", "(%recv%).map { |__e| %a0%.call(__e) }")
      m["filter"]    = BuiltinMethod.new("filter", ["Fn(#{t}):Bool"], "List<#{t}>", "(%recv%).select { |__e| %a0%.call(__e) }")
      m["reduce"]    = BuiltinMethod.new("reduce", ["?", "Fn(?,#{t}):?"], "?", "(%recv%).reduce(%a0%) { |__acc, __e| %a1%.call(__acc, __e) }")
      m["find"]      = BuiltinMethod.new("find", ["Fn(#{t}):Bool"], t, "((%recv%).find { |__e| %a0%.call(__e) }).not_nil!")
      m["any"]       = BuiltinMethod.new("any", ["Fn(#{t}):Bool"], "Bool", "(%recv%).any? { |__e| %a0%.call(__e) }")
      m["all"]       = BuiltinMethod.new("all", ["Fn(#{t}):Bool"], "Bool", "(%recv%).all? { |__e| %a0%.call(__e) }")
      m["toString"]  = BuiltinMethod.new("toString", [] of String, "String", "(%recv%).to_s")
      m
    end

    def map_methods(k : String, v : String) : Hash(String, BuiltinMethod)
      m = {} of String => BuiltinMethod
      m["length"]   = BuiltinMethod.new("length", [] of String, "Int", "(%recv%).size.to_i64")
      m["isEmpty"]  = BuiltinMethod.new("isEmpty", [] of String, "Bool", "(%recv%).empty?")
      m["get"]      = BuiltinMethod.new("get", [k], v, "(%recv%)[%a0%]")
      m["put"]      = BuiltinMethod.new("put", [k, v], "Void", "(%recv%)[%a0%] = %a1%")
      m["remove"]   = BuiltinMethod.new("remove", [k], "Bool", "((%recv%).delete(%a0%) != nil)")
      m["has"]      = BuiltinMethod.new("has", [k], "Bool", "(%recv%).has_key?(%a0%)")
      m["keys"]     = BuiltinMethod.new("keys", [] of String, "List<#{k}>", "(%recv%).keys")
      m["values"]   = BuiltinMethod.new("values", [] of String, "List<#{v}>", "(%recv%).values")
      m["clear"]    = BuiltinMethod.new("clear", [] of String, "Void", "(%recv%).clear")
      m["forEach"]  = BuiltinMethod.new("forEach", ["Fn(#{k},#{v}):Void"], "Void", "(%recv%).each { |__k, __v| %a0%.call(__k, __v) }")
      m["toString"] = BuiltinMethod.new("toString", [] of String, "String", "(%recv%).to_s")
      m
    end

    def set_methods(t : String) : Hash(String, BuiltinMethod)
      m = {} of String => BuiltinMethod
      m["length"]     = BuiltinMethod.new("length", [] of String, "Int", "(%recv%).size.to_i64")
      m["isEmpty"]    = BuiltinMethod.new("isEmpty", [] of String, "Bool", "(%recv%).empty?")
      m["add"]        = BuiltinMethod.new("add", [t], "Void", "(%recv%) << %a0%")
      m["remove"]     = BuiltinMethod.new("remove", [t], "Bool", "((%recv%).delete(%a0%) != nil)")
      m["contains"]   = BuiltinMethod.new("contains", [t], "Bool", "(%recv%).includes?(%a0%)")
      m["clear"]      = BuiltinMethod.new("clear", [] of String, "Void", "(%recv%).clear")
      m["union"]      = BuiltinMethod.new("union", ["Set<#{t}>"], "Set<#{t}>", "(%recv%) | %a0%")
      m["intersect"]  = BuiltinMethod.new("intersect", ["Set<#{t}>"], "Set<#{t}>", "(%recv%) & %a0%")
      m["difference"] = BuiltinMethod.new("difference", ["Set<#{t}>"], "Set<#{t}>", "(%recv%) - %a0%")
      m["forEach"]    = BuiltinMethod.new("forEach", ["Fn(#{t}):Void"], "Void", "(%recv%).each { |__e| %a0%.call(__e) }")
      m["toString"]   = BuiltinMethod.new("toString", [] of String, "String", "(%recv%).to_s")
      m
    end
  end
end
