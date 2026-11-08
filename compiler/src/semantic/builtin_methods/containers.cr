require "../builtin_methods"

module Emerald
  module BuiltinMethods
    extend self
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
