require "../builtin_methods"

module Emerald
  module BuiltinMethods
    extend self
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
      m["toUpperCase"] = BuiltinMethod.new("toUpperCase", [] of String, "String", "(%recv%).upcase")
      m["toLowerCase"] = BuiltinMethod.new("toLowerCase", [] of String, "String", "(%recv%).downcase")
      m["isBlank"]     = BuiltinMethod.new("isBlank", [] of String, "Bool", "(%recv%).strip.empty?")
      m["equals"]      = BuiltinMethod.new("equals", ["String"], "Bool", "((%recv%) == (%a0%))")
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

  end
end
