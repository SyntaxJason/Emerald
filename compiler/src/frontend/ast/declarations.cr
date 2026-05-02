require "./nodes"
require "./types"

module Emerald
  module AST
    class Param < Node
      property type_ref : TypeRef
      property name : String

      def initialize(@type_ref, @name); end
    end

    class VarDecl < Node
      property mutability : Mutability
      property type_ref : TypeRef?
      property name : String
      property initializer : Node?

      def initialize(@mutability, @type_ref, @name, @initializer); end
    end

    class FieldDecl < Node
      property visibility : Visibility
      property mutability : Mutability
      property type_ref : TypeRef
      property name : String
      property initializer : Node?

      def initialize(@visibility, @mutability, @type_ref, @name, @initializer = nil); end
    end

    class MethodDecl < Node
      property visibility : Visibility
      property name : String
      property params : Array(Param)
      property return_type : TypeRef
      property body : Block?
      property is_override : Bool
      property is_default : Bool
      property is_abstract : Bool

      def initialize(@visibility, @name, @params, @return_type, @body,
                     @is_override = false, @is_default = false, @is_abstract = false); end
    end

    class ConstructorDecl < Node
      property visibility : Visibility
      property params : Array(Param)
      property body : Block

      def initialize(@visibility, @params, @body); end
    end

    class FunctionDecl < Node
      property visibility : Visibility
      property name : String
      property params : Array(Param)
      property return_type : TypeRef
      property body : Block
      property namespace : String

      def initialize(@visibility, @name, @params, @return_type, @body)
        @namespace = ""
      end
    end

    class MainDecl < Node
      property body : Block

      def initialize(@body); end
    end

    class ClassDecl < Node
      property visibility : Visibility
      property name : String
      property is_data : Bool
      property is_abstract : Bool
      property base : String?
      property interfaces : Array(String)
      property fields : Array(FieldDecl)
      property methods : Array(MethodDecl)
      property constructors : Array(ConstructorDecl)
      property namespace : String
      property type_params : Array(String)

      def initialize(@visibility, @name, @is_data, @is_abstract,
                     @base, @interfaces, @fields, @methods, @constructors,
                     @type_params = [] of String)
        @namespace = ""
      end
    end

    class InterfaceDecl < Node
      property visibility : Visibility
      property name : String
      property extends_interfaces : Array(String)
      property methods : Array(MethodDecl)
      property namespace : String
      property type_params : Array(String)

      def initialize(@visibility, @name, @extends_interfaces, @methods)
        @namespace = ""
        @type_params = [] of String
      end
    end

    class AliasDecl < Node
      property name : String
      property target : QualifiedName

      def initialize(@name, @target); end
    end
  end
end
