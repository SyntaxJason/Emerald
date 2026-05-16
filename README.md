# Emerald

Emerald is an experimental Java-inspired language with Crystal-backed native code generation.

The language is currently in an experimental stage, but already includes a working compiler pipeline with parsing, resolving, type checking, macro expansion and Crystal code generation.

## Current focus

Emerald aims to combine:

```txt
Java-like structure
Crystal-like ergonomics
Emerald-specific compile-time power
```

The language is designed to be easy to enter without requiring OOP knowledge immediately, while still growing naturally into object-oriented and concurrent programming.

## Current features

```txt
classes
interfaces
generics
namespaces
use imports / aliases
methods
constructors
fields
visibility modifiers
annotations
compile-time macros
quote / unquote macro templates
fibers
threads
virtual threads
channels
mutex / synchronized
positive example tests
negative compiler tests
diagnostics with source snippets
```

## Project layout

```txt
compiler/    Emerald compiler
stdlib/      Emerald standard library sources
```

Only `compiler/` and `stdlib/` are intended to be versioned as project code.

## Build

```bash
cd compiler
shards build emeraldc
```

or from the project root, if `emerald.sh` is available:

```bash
./emerald.sh build
```

## Test

Run positive examples:

```bash
./emerald.sh positive
```

Run negative tests:

```bash
./emerald.sh negative
```

Run the full suite without rebuilding:

```bash
./emerald.sh test --no-build
```

## Standard library direction

The STDLib is planned to be interface-first.

Namespace layout:

```txt
Std::Collections
Std::Compare
Std::Data
Std::Functional
Std::Io
Std::Math
Std::Option
Std::Result
Std::Time
```

The next major STDLib targets are:

```txt
Std::Collections::ArrayList<T>
Std::Collections::HashMap<K, V>
Std::Io::File
Std::Io::Path
Std::Io::TextReader
Std::Io::TextWriter
```

The STDLib should avoid hidden compiler magic where possible. Library behavior should be implemented as normal Emerald code first.

API conventions are documented in `STD_API_STYLE.md`.

## Macro system

Emerald macros are designed to feel like Java annotations with real compiler-time power.

Example:

```ems
macro Logged on Method {
    StatementAST entry = quote stmt {
        println("enter");
    };

    method.body.prepend(entry);
}

public class Service {
    @Logged
    public Void run() {
        println("body");
    }
}
```

## Quote / Unquote

```ems
quote expr   { ... }
quote stmt   { ... }
quote block  { ... }
quote method { ... }
quote field  { ... }
```

Unquote:

```ems
$(value)
```

Example:

```ems
ExpressionAST message = Expr::str("hello");

StatementAST stmt = quote stmt {
    println($(message));
};
```

## Imports and namespaces

Emerald currently follows a PHP-like namespace/import direction using `::`.

```ems
namespace App::Auth;

public class User {
}
```

```ems
use App::Auth::User as AuthUser;
```

Aliases should be used when different namespaces contain classes with the same simple name.

## Status

Emerald is experimental.

APIs, syntax and compiler internals may still change heavily while the language is being shaped.
