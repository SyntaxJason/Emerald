module Emerald
  class BuiltinFunction
    getter fqn : String
    getter param_types : Array(String)
    getter return_type : String
    getter crystal_template : String

    def initialize(@fqn, @param_types, @return_type, @crystal_template); end
  end

  module BuiltinFunctions
    extend self

    @@all : Hash(String, BuiltinFunction)?

    def all : Hash(String, BuiltinFunction)
      @@all ||= build_all
    end

    def for_fqn(fqn : String) : BuiltinFunction?
      all[fqn]?
    end

    private def build_all : Hash(String, BuiltinFunction)
      m = {} of String => BuiltinFunction
      add_math(m)
      add_io(m)
      add_time(m)
      add_macro_builders(m)
      m
    end

    private def add_math(m : Hash(String, BuiltinFunction))
      add(m, "Emerald::Math::pi",        [] of String, "Float", "Math::PI")
      add(m, "Emerald::Math::e",         [] of String, "Float", "Math::E")
      add(m, "Emerald::Math::sqrt",      ["Float"],    "Float", "Math.sqrt(%a0%)")
      add(m, "Emerald::Math::pow",       ["Float", "Float"], "Float", "(%a0%) ** (%a1%)")
      add(m, "Emerald::Math::floor",     ["Float"],    "Float", "(%a0%).floor")
      add(m, "Emerald::Math::ceil",      ["Float"],    "Float", "(%a0%).ceil")
      add(m, "Emerald::Math::round",     ["Float"],    "Float", "(%a0%).round")
      add(m, "Emerald::Math::sin",       ["Float"],    "Float", "Math.sin(%a0%)")
      add(m, "Emerald::Math::cos",       ["Float"],    "Float", "Math.cos(%a0%)")
      add(m, "Emerald::Math::tan",       ["Float"],    "Float", "Math.tan(%a0%)")
      add(m, "Emerald::Math::log",       ["Float"],    "Float", "Math.log(%a0%)")
      add(m, "Emerald::Math::log10",     ["Float"],    "Float", "Math.log10(%a0%)")
      add(m, "Emerald::Math::exp",       ["Float"],    "Float", "Math.exp(%a0%)")
      add(m, "Emerald::Math::absFloat",  ["Float"],    "Float", "(%a0%).abs")
      add(m, "Emerald::Math::random",    [] of String, "Float", "rand")
      add(m, "Emerald::Math::randomInt", ["Int", "Int"], "Int", "(rand((%a0%).to_i64..(%a1%).to_i64)).to_i64")
      add(m, "Emerald::Math::min",       ["Int", "Int"], "Int", "([%a0%, %a1%].min)")
      add(m, "Emerald::Math::max",       ["Int", "Int"], "Int", "([%a0%, %a1%].max)")
    end

    private def add_io(m : Hash(String, BuiltinFunction))
      add(m, "Emerald::IO::readFile",  ["String"], "Result<String,String>",
          "(begin; EmeraldResult.ok(File.read(%a0%)); rescue ex : Exception; EmeraldResult.err(ex.message || \"IO error\"); end)")
      add(m, "Emerald::IO::writeFile", ["String", "String"], "Result<Void,String>",
          "(begin; File.write(%a0%, %a1%); EmeraldResult.ok(nil); rescue ex : Exception; EmeraldResult.err(ex.message || \"IO error\"); end)")
      add(m, "Emerald::IO::readLine",  [] of String, "String", "(gets || \"\")")
      add(m, "Emerald::IO::print",     ["String"], "Void", "print(%a0%)")
      add(m, "Emerald::IO::println",   ["String"], "Void", "puts(%a0%)")
      add(m, "Emerald::IO::exists",    ["String"], "Bool", "(File.exists?(%a0%) || Dir.exists?(%a0%))")
    end

    private def add_time(m : Hash(String, BuiltinFunction))
      add(m, "Emerald::Time::now",        [] of String, "Int", "(Time.utc.to_unix_ms)")
      add(m, "Emerald::Time::nowSeconds", [] of String, "Int", "(Time.utc.to_unix)")
      add(m, "Emerald::Time::sleep", ["Int"], "Void", "sleep((%a0%).milliseconds)")
    end

    private def add_macro_builders(m : Hash(String, BuiltinFunction))
      add(m, "Stmt::expr",       ["ExpressionAST"], "StatementAST", "(%a0%)")
      add(m, "Stmt::return",     ["ExpressionAST"], "StatementAST", "(%a0%)")
      add(m, "Stmt::returnVoid", [] of String, "StatementAST", "nil")
      add(m, "Stmt::var",        ["String", "String", "ExpressionAST"], "StatementAST", "(%a0%)")
      add(m, "Stmt::assign",     ["String", "ExpressionAST"], "StatementAST", "(%a0%)")
      add(m, "Stmt::if",         ["ExpressionAST", "BlockAST"], "StatementAST", "(%a0%)")
      add(m, "Stmt::ifElse",     ["ExpressionAST", "BlockAST", "BlockAST"], "StatementAST", "(%a0%)")
      add(m, "Stmt::while",      ["ExpressionAST", "BlockAST"], "StatementAST", "(%a0%)")

      add(m, "Expr::int",            ["Int"], "ExpressionAST", "(%a0%)")
      add(m, "Expr::float",          ["Float"], "ExpressionAST", "(%a0%)")
      add(m, "Expr::str",            ["String"], "ExpressionAST", "(%a0%)")
      add(m, "Expr::bool",           ["Bool"], "ExpressionAST", "(%a0%)")
      add(m, "Expr::ident",          ["String"], "ExpressionAST", "(%a0%)")
      add(m, "Expr::this",           [] of String, "ExpressionAST", "(%a0%)")
      add(m, "Expr::call",           ["String", "List<ExpressionAST>"], "ExpressionAST", "(%a0%)")
      add(m, "Expr::methodCall",     ["ExpressionAST", "String", "List<ExpressionAST>"], "ExpressionAST", "(%a0%)")
      add(m, "Expr::memberAccess",   ["ExpressionAST", "String"], "ExpressionAST", "(%a0%)")
      add(m, "Expr::binary",         ["String", "ExpressionAST", "ExpressionAST"], "ExpressionAST", "(%a0%)")

      add(m, "Block::of",    ["List<StatementAST>"], "BlockAST", "(%a0%)")
      add(m, "Block::empty", [] of String, "BlockAST", "nil")

      add(m, "MethodAST::create", ["String", "String", "List<ParamAST>", "BlockAST"], "MethodAST", "(%a0%)")
    end

    private def add(m : Hash(String, BuiltinFunction), fqn : String, params : Array(String), ret : String, tmpl : String)
      m[fqn] = BuiltinFunction.new(fqn, params, ret, tmpl)
    end
  end
end
