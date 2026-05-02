module Emerald
  enum TokenType
    IntLit
    FloatLit
    StringLit
    InterpString
    CharLit
    TrueLit
    FalseLit

    Identifier

    KwInt
    KwFloat
    KwBool
    KwChar
    KwString
    KwVoid

    KwFinal
    KwCryo
    KwPublic
    KwPrivate
    KwProtected
    KwInternal

    KwIf
    KwElse
    KwWhile
    KwFor
    KwIn
    KwReturn
    KwBreak
    KwContinue

    KwClass
    KwInterface
    KwData
    KwExtends
    KwImplements
    KwThis
    KwDefault
    KwNew
    KwAbstract

    KwMatch
    KwIs

    KwNamespace
    KwAlias
    KwMain

    LParen
    RParen
    LBrace
    RBrace
    LBracket
    RBracket
    Comma
    Semicolon
    Dot
    Arrow

    Plus
    Minus
    Star
    Slash
    Percent
    Eq
    EqEq
    NotEq
    Lt
    Gt
    LtEq
    GtEq
    AndAnd
    OrOr
    Bang
    DotDot

    At
    Colon
    ColonColon

    EOF
  end

  struct InterpPart
    enum Kind
      Text
      Expr
    end

    getter kind : Kind
    getter content : String

    def initialize(@kind, @content); end
  end

  class Token
    getter type : TokenType
    getter value : String
    getter line : Int32
    getter col : Int32
    getter parts : Array(InterpPart)?

    def initialize(@type, @value, @line, @col, @parts = nil); end

    def to_s(io : IO)
      io << "Token(" << @type << ", " << @value.inspect << ", " << @line << ":" << @col << ")"
    end
  end
end
