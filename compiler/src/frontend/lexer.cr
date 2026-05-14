require "./token"

module Emerald
  class LexError < Exception
    getter line : Int32
    getter col : Int32

    def initialize(message : String, @line, @col)
      super("#{message} at #{@line}:#{@col}")
    end
  end

  class Lexer
    KEYWORDS = {
      "Int"        => TokenType::KwInt,
      "Float"      => TokenType::KwFloat,
      "Bool"       => TokenType::KwBool,
      "Char"       => TokenType::KwChar,
      "String"     => TokenType::KwString,
      "Void"       => TokenType::KwVoid,
      "final"      => TokenType::KwFinal,
      "cryo"       => TokenType::KwCryo,
      "public"     => TokenType::KwPublic,
      "private"    => TokenType::KwPrivate,
      "protected"  => TokenType::KwProtected,
      "internal"   => TokenType::KwInternal,
      "if"         => TokenType::KwIf,
      "else"       => TokenType::KwElse,
      "while"      => TokenType::KwWhile,
      "for"        => TokenType::KwFor,
      "in"         => TokenType::KwIn,
      "return"     => TokenType::KwReturn,
      "break"      => TokenType::KwBreak,
      "continue"   => TokenType::KwContinue,
      "class"      => TokenType::KwClass,
      "interface"  => TokenType::KwInterface,
      "data"       => TokenType::KwData,
      "extends"    => TokenType::KwExtends,
      "implements" => TokenType::KwImplements,
      "this"       => TokenType::KwThis,
      "default"    => TokenType::KwDefault,
      "abstract"   => TokenType::KwAbstract,
      "match"      => TokenType::KwMatch,
      "is"         => TokenType::KwIs,
      "namespace"  => TokenType::KwNamespace,
      "use"        => TokenType::KwUse,
      "as"         => TokenType::KwAs,
      "alias"      => TokenType::KwAlias,
      "main"       => TokenType::KwMain,
      "macro"      => TokenType::KwMacro,
      "on"         => TokenType::KwOn,
      "true"       => TokenType::TrueLit,
      "false"      => TokenType::FalseLit,
    }

    def initialize(@source : String)
      @pos = 0
      @line = 1
      @col = 1
    end

    def tokenize : Array(Token)
      tokens = [] of Token
      loop do
        skip_whitespace_and_comments
        break if @pos >= @source.size

        c = @source[@pos]
        case
        when c == '"'
          tokens << read_string
        when c == '\''
          tokens << read_char
        when c.ascii_number?
          tokens << read_number
        when c.ascii_letter? || c == '_'
          tokens << read_identifier_or_keyword
        else
          tokens << read_operator_or_punct
        end
      end
      tokens << Token.new(TokenType::EOF, "", @line, @col)
      tokens
    end
  end
end

require "./lexer/scanning"
require "./lexer/literals"
require "./lexer/punctuation"
