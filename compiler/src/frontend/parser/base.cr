require "../token"
require "../ast"

module Emerald
  class ParseError < Exception
    getter line : Int32
    getter col : Int32

    def initialize(message : String, @line, @col)
      super("#{message} at #{@line}:#{@col}")
    end
  end

  class Parser
    PREC_ASSIGN = 1
    PREC_OR     = 2
    PREC_AND    = 3
    PREC_EQ     = 4
    PREC_CMP    = 5
    PREC_RANGE  = 6
    PREC_ADD    = 7
    PREC_MUL    = 8
    PREC_UNARY  = 9

    BINARY_OPS = {
      TokenType::OrOr    => {prec: PREC_OR,    right_assoc: false, name: "||"},
      TokenType::AndAnd  => {prec: PREC_AND,   right_assoc: false, name: "&&"},
      TokenType::EqEq    => {prec: PREC_EQ,    right_assoc: false, name: "=="},
      TokenType::NotEq   => {prec: PREC_EQ,    right_assoc: false, name: "!="},
      TokenType::Lt      => {prec: PREC_CMP,   right_assoc: false, name: "<"},
      TokenType::Gt      => {prec: PREC_CMP,   right_assoc: false, name: ">"},
      TokenType::LtEq    => {prec: PREC_CMP,   right_assoc: false, name: "<="},
      TokenType::GtEq    => {prec: PREC_CMP,   right_assoc: false, name: ">="},
      TokenType::DotDot  => {prec: PREC_RANGE, right_assoc: false, name: ".."},
      TokenType::Plus    => {prec: PREC_ADD,   right_assoc: false, name: "+"},
      TokenType::Minus   => {prec: PREC_ADD,   right_assoc: false, name: "-"},
      TokenType::Star    => {prec: PREC_MUL,   right_assoc: false, name: "*"},
      TokenType::Slash   => {prec: PREC_MUL,   right_assoc: false, name: "/"},
      TokenType::Percent => {prec: PREC_MUL,   right_assoc: false, name: "%"},
    }

    def initialize(@tokens : Array(Token))
      @pos = 0
    end

    def parse : AST::Program
      program = AST::Program.new
      if peek.type == TokenType::KwNamespace
        program.namespace_decl = parse_namespace_decl
      end
      until at_end?
        program.declarations << parse_top_level
      end
      program
    end

    private def parse_namespace_decl : AST::QualifiedName
      tok = expect(TokenType::KwNamespace)
      segments = [] of String
      segments << expect(TokenType::Identifier).value
      while peek.type == TokenType::ColonColon
        consume
        segments << expect(TokenType::Identifier).value
      end
      expect(TokenType::Semicolon)
      AST::QualifiedName.new(segments).at(tok.line, tok.col).as(AST::QualifiedName)
    end

    def peek : Token
      @tokens[@pos]
    end

    def peek_at(i : Int32) : Token?
      return nil if i >= @tokens.size
      @tokens[i]
    end

    def consume : Token
      tok = @tokens[@pos]
      @pos += 1
      tok
    end

    def at_end? : Bool
      peek.type == TokenType::EOF
    end

    def expect(type : TokenType) : Token
      tok = consume
      unless tok.type == type
        raise ParseError.new("Expected #{type}, got #{tok.type} ('#{tok.value}')", tok.line, tok.col)
      end
      tok
    end

    private def parse_visibility : AST::Visibility
      case peek.type
      when TokenType::KwPublic    then consume; AST::Visibility::Public
      when TokenType::KwPrivate   then consume; AST::Visibility::Private
      when TokenType::KwProtected then consume; AST::Visibility::Protected
      when TokenType::KwInternal  then consume; AST::Visibility::Internal
      else                             AST::Visibility::Public
      end
    end

    private def parse_mutability : AST::Mutability
      case peek.type
      when TokenType::KwFinal then consume; AST::Mutability::Final
      when TokenType::KwCryo  then consume; AST::Mutability::Cryo
      else                         AST::Mutability::Mutable
      end
    end
  end
end
