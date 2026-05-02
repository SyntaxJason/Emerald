require "../frontend/ast"

module Emerald
  module TypeSystem
    extend self

    def type_ref_name(ref : AST::TypeRef) : String
      case ref
      when AST::NamedType
        ref.as(AST::NamedType).name
      when AST::FunctionType
        ft = ref.as(AST::FunctionType)
        params = ft.param_types.map { |p| type_ref_name(p) }.join(",")
        "Fn(#{params}):#{type_ref_name(ft.return_type)}"
      when AST::GenericType
        gt = ref.as(AST::GenericType)
        args = gt.type_args.map { |a| type_ref_name(a) }.join(",")
        "#{gt.name}<#{args}>"
      else
        "Unknown"
      end
    end

    def numeric?(t : String) : Bool
      t == "Int" || t == "Float"
    end

    def promote_numeric(a : String, b : String) : String
      return "Float" if a == "Float" || b == "Float"
      "Int"
    end

    def parse_fn_type_string(t : String) : {Array(String), String}
      inner = t[3..-1]
      colon_idx = inner.rindex("):") || inner.size
      params_part = inner[0...colon_idx]
      ret_part = colon_idx < inner.size ? inner[(colon_idx + 2)..] : "Void"
      params = params_part.empty? ? [] of String : params_part.split(",").map(&.strip)
      {params, ret_part.strip}
    end

    def result_inner_ok_type(t : String) : String
      return "Object" unless t.starts_with?("Result<")
      inner = t[7..-2]
      parts = inner.split(",", 2)
      parts[0]
    end

    def result_inner_err_type(t : String) : String
      return "Object" unless t.starts_with?("Result<")
      inner = t[7..-2]
      parts = inner.split(",", 2)
      parts[1]
    end

    def unify_result_types(a : String, b : String) : String
      a_inner = a[7..-2]
      b_inner = b[7..-2]
      a_parts = a_inner.split(",", 2)
      b_parts = b_inner.split(",", 2)
      ok = a_parts[0] == "?" ? b_parts[0] : a_parts[0]
      err = a_parts[1] == "?" ? b_parts[1] : a_parts[1]
      "Result<#{ok},#{err}>"
    end
  end
end
