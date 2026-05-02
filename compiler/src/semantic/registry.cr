require "../frontend/ast"
require "./scope"

module Emerald
  class FieldInfo
    getter name : String
    getter type_name : String
    getter visibility : AST::Visibility

    def initialize(@name, @type_name, @visibility); end
  end

  class MethodInfo
    getter name : String
    getter param_types : Array(String)
    getter return_type : String
    getter visibility : AST::Visibility
    getter is_abstract : Bool

    def initialize(@name, @param_types, @return_type, @visibility, @is_abstract = false); end
  end

  class ConstructorInfo
    getter param_types : Array(String)
    getter visibility : AST::Visibility

    def initialize(@param_types, @visibility); end
  end

  class ClassInfo
    getter name : String
    getter fqn : String
    getter is_data : Bool
    getter is_abstract : Bool
    getter is_interface : Bool
    property base : String?
    property interfaces : Array(String)
    property fields : Hash(String, FieldInfo)
    property methods : Hash(String, MethodInfo)
    property constructors : Array(ConstructorInfo)
    property type_params : Array(String)

    def initialize(@name, @fqn, @is_data = false, @is_abstract = false, @is_interface = false)
      @base = nil
      @interfaces = [] of String
      @fields = {} of String => FieldInfo
      @methods = {} of String => MethodInfo
      @constructors = [] of ConstructorInfo
      @type_params = [] of String
    end
  end

  class ClassRegistry
    getter classes : Hash(String, ClassInfo)
    getter by_simple_name : Hash(String, Array(String))

    def initialize
      @classes = {} of String => ClassInfo
      @by_simple_name = {} of String => Array(String)
    end

    def register(info : ClassInfo, line : Int32, col : Int32)
      if @classes.has_key?(info.fqn)
        raise ResolveError.new("Type '#{info.fqn}' already declared", line, col)
      end
      @classes[info.fqn] = info
      @by_simple_name[info.name] ||= [] of String
      @by_simple_name[info.name] << info.fqn
    end

    def [](fqn : String) : ClassInfo?
      @classes[fqn]?
    end

    def resolve_simple(name : String) : Array(String)
      @by_simple_name[name]? || [] of String
    end

    def assignable?(child : String, parent : String) : Bool
      return true if child == parent
      info = @classes[child]?
      return false unless info
      if base = info.base
        return true if assignable?(base, parent)
      end
      info.interfaces.each do |iface|
        return true if assignable?(iface, parent)
      end
      false
    end

    def lookup_method(class_name : String, method_name : String) : MethodInfo?
      info = @classes[class_name]?
      return nil unless info
      if m = info.methods[method_name]?
        return m
      end
      if base = info.base
        if m = lookup_method(base, method_name)
          return m
        end
      end
      info.interfaces.each do |iface|
        if m = lookup_method(iface, method_name)
          return m
        end
      end
      nil
    end

    def lookup_field(class_name : String, field_name : String) : FieldInfo?
      info = @classes[class_name]?
      return nil unless info
      if f = info.fields[field_name]?
        return f
      end
      if base = info.base
        return lookup_field(base, field_name)
      end
      nil
    end
  end
end
