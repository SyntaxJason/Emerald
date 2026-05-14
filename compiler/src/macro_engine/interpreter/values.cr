require "../../frontend/ast"

module Emerald
  module MacroEngine
    abstract class MacroValue
    end

    class MacroInt < MacroValue
      property value : Int64
      def initialize(@value); end
    end

    class MacroFloat < MacroValue
      property value : Float64
      def initialize(@value); end
    end

    class MacroString < MacroValue
      property value : String
      def initialize(@value); end
    end

    class MacroBool < MacroValue
      property value : Bool
      def initialize(@value); end
    end

    class MacroList < MacroValue
      property value : Array(MacroValue)

      def initialize
        @value = [] of MacroValue
      end

      def self.from(items : Array(MacroValue)) : MacroList
        list = MacroList.new
        items.each { |item| list.value << item }
        list
      end
    end

    class MacroASTRef < MacroValue
      property node : AST::Node
      property type_name : String
      def initialize(@node, @type_name); end
    end

    class MacroVoid < MacroValue
    end

    class MacroScope
      property parent : MacroScope?
      property variables : Hash(String, MacroValue)

      def initialize(@parent = nil)
        @variables = {} of String => MacroValue
      end

      def declare(name : String, value : MacroValue)
        @variables[name] = value
      end

      def lookup(name : String) : MacroValue?
        if v = @variables[name]?
          return v
        end
        @parent.try &.lookup(name)
      end

      def set(name : String, value : MacroValue)
        if @variables.has_key?(name)
          @variables[name] = value
        elsif p = @parent
          p.set(name, value)
        end
      end
    end


    class MacroReturn < Exception
      getter value : MacroValue

      def initialize(@value); end
    end
  end
end
