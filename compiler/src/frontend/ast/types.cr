require "./nodes"

module Emerald
  module AST
    abstract class TypeRef < Node
    end

    class NamedType < TypeRef
      property name : String

      def initialize(@name); end
    end

    class FunctionType < TypeRef
      property param_types : Array(TypeRef)
      property return_type : TypeRef

      def initialize(@param_types, @return_type); end
    end

    class GenericType < TypeRef
      property name : String
      property type_args : Array(TypeRef)

      def initialize(@name, @type_args); end
    end
  end
end
