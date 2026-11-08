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


  end
end

require "./builtin_methods/primitives"
require "./builtin_methods/containers"
