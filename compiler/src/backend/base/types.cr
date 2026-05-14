require "../base"

module Emerald
  class Codegen
    def crystal_type(t : String) : String
      case t
      when "Int"    then "Int64"
      when "Float"  then "Float64"
      when "Bool"   then "Bool"
      when "Char"   then "Char"
      when "String" then "String"
      when "Void"   then "Nil"
      when "Any"    then "Object"
      else
        if t.starts_with?("Result<")
          "EmeraldResult"
        elsif t.starts_with?("List<")
          inner = BuiltinMethods.extract_type_arg(t)
          "Array(#{crystal_type(inner)})"
        elsif t.starts_with?("Map<")
          k, v = BuiltinMethods.extract_type_args2(t)
          "Hash(#{crystal_type(k)}, #{crystal_type(v)})"
        elsif t.starts_with?("Set<")
          inner = BuiltinMethods.extract_type_arg(t)
          "Set(#{crystal_type(inner)})"
        elsif t.starts_with?("Fiber<")
          inner = t[(t.index("<").not_nil! + 1)..-2]
          "EmeraldFiber(#{crystal_type(inner)})"
        elsif t.starts_with?("VirtualThread<")
          inner = t[(t.index("<").not_nil! + 1)..-2]
          "EmeraldFiber(#{crystal_type(inner)})"
        elsif t.starts_with?("Thread<")
          inner = t[(t.index("<").not_nil! + 1)..-2]
          "EmeraldThread(#{crystal_type(inner)})"
        elsif t.starts_with?("Channel<")
          inner = t[(t.index("<").not_nil! + 1)..-2]
          "Channel(#{crystal_type(inner)})"
        elsif t == "Mutex"
          "Mutex"
        elsif t.starts_with?("Fn(")
          inner = t[3..-1]
          colon_idx = inner.rindex("):") || inner.size
          params_part = inner[0...colon_idx]
          ret_part = colon_idx < inner.size ? inner[(colon_idx + 2)..] : "Nil"
          params = params_part.empty? ? [] of String : params_part.split(",")
          crystal_params = params.map { |p| crystal_type(p.strip) }
          ret_crystal = crystal_type(ret_part.strip)
          if crystal_params.empty?
            "Proc(#{ret_crystal})"
          else
            "Proc(#{crystal_params.join(", ")}, #{ret_crystal})"
          end
        elsif t.includes?("<") && t.ends_with?(">")
          gen_open = t.index("<").not_nil!
          base = t[0...gen_open]
          args_str = t[(gen_open + 1)..-2]
          args = split_top_level_args(args_str)
          crystal_args = args.map { |a| crystal_type(a.strip) }
          "#{mangle_fqn(base)}(#{crystal_args.join(", ")})"
        else
          mangle_fqn(t)
        end
      end
    end

    private def split_top_level_args(s : String) : Array(String)
      result = [] of String
      depth = 0
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

    def mangle_fqn(fqn : String) : String
      fqn.gsub("::", "_")
    end

    def mangle_fn_fqn(fqn : String) : String
      mangled = fqn.gsub("::", "_")
      return mangled if mangled.empty?
      first = mangled[0]
      first.uppercase? ? "#{first.downcase}#{mangled[1..]}" : mangled
    end

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

  end
end
