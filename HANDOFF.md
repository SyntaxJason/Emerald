# Emerald – Project Hand-off

This document brings any AI assistant up to speed on the Emerald compiler project. Read this first before making changes.

## What Emerald Is

Emerald is a statically typed, compiled programming language created by SyntaxJason. It is implemented as a **source-to-source compiler**: Emerald source (`.ems`) is translated to Crystal source code, which Crystal then compiles to a native binary.

The compiler is itself written in Crystal, in a project called `emeraldc`.

The language design pulls from Java (familiar OOP syntax, visibility keywords), Kotlin (data classes, trailing lambdas, `it`), Rust (Result type, no nulls), and Scala (pattern matching). The goal is a language that feels familiar to JVM developers but with a strong type system, structured concurrency, and macro-based code generation as a long-term killer feature.

## Project State (Sprint 6 in progress)

Six sprints have been completed or are in progress. Each adds a bundle of features. Sprints 1-5 are committed and working. Sprint 6 is implemented but had 3 bugs at last contact, with fixes attempted in the most recent zip. Build state is unknown - the user may need to verify.

| Sprint | Theme | Status |
|--------|-------|--------|
| 1 | Foundation: lexer, parser, AST, resolver, type-checker, codegen, primitives, control flow, functions | ✅ Working |
| 2 | OOP: classes, inheritance, interfaces, data classes, constructors | ✅ Working |
| 3 | Lambdas, pattern matching, Result type, MethodRefs | ✅ Working |
| 4 | OOP refactor of compiler internals, `main()`, auto-imports, namespaces | ✅ Working |
| 5 | Stdlib v1: List/Map/Set built-ins, primitive methods, Math/IO/Time | ✅ Working |
| 6 | User-generics, concurrency (Fiber/Thread/VirtualThread/Channel/Mutex), trailing lambdas | 🟡 In progress, recent fixes applied for: `new` keyword removal, `current_type_params` in TypeChecker, trailing-lambda last-expression-without-semicolon |
| 7 | Macros / Annotations | 🔮 Future |

## Architecture

```
compiler/
├── shard.yml                        # Crystal package config
└── src/
    ├── emeraldc.cr                  # CLI entry
    ├── driver.cr                    # Pipeline coordinator
    ├── frontend/
    │   ├── token.cr
    │   ├── lexer.cr
    │   ├── ast.cr                   # Aggregator
    │   ├── ast/                     # Per-domain AST nodes
    │   │   ├── nodes.cr
    │   │   ├── types.cr
    │   │   ├── declarations.cr
    │   │   ├── statements.cr
    │   │   ├── expressions.cr
    │   │   └── patterns.cr
    │   ├── parser.cr                # Aggregator
    │   └── parser/                  # Per-area parsing
    │       ├── base.cr
    │       ├── types.cr
    │       ├── patterns.cr
    │       ├── expressions.cr
    │       ├── statements.cr
    │       └── declarations.cr
    ├── semantic/
    │   ├── scope.cr                 # Symbol hierarchy
    │   ├── registry.cr              # Class registry
    │   ├── namespace.cr             # FQN resolution
    │   ├── type_system.cr           # Type helpers
    │   ├── builtin_methods.cr       # Methods on String/Int/List/Map/Set/etc.
    │   ├── builtin_functions.cr     # Math::sqrt, IO::readFile, etc.
    │   ├── resolver.cr
    │   └── type_checker.cr
    ├── backend/
    │   ├── codegen.cr               # Aggregator
    │   ├── base.cr                  # Crystal-type mapping, helpers
    │   ├── declarations.cr
    │   ├── statements.cr
    │   ├── expressions.cr
    │   ├── match_lowering.cr
    │   ├── concurrency.cr           # Fiber/Thread/Channel/Mutex codegen
    │   └── runtime_prelude.cr       # EmeraldResult, EmeraldFiber, EmeraldThread
    └── runtime/
        ├── stdlib_loader.cr
        └── project_loader.cr        # Multi-file project discovery
```

## Pipeline

```
.ems source
  → Lexer (token stream, with InterpString tokens for "$()" interp)
  → Parser (Pratt-style for expressions, recursive-descent for declarations)
  → Resolver (symbol table, namespace resolution, class registry)
  → TypeChecker (with type substitution for generics)
  → Codegen (emits Crystal source)
  → Crystal compiler (invoked via Process.run)
  → Native binary
```

## Language Design Reference

### Visibility & Mutability

Three orthogonal axes per declaration:
- **Visibility**: `public` (default) / `private` / `protected` / `internal`
- **Mutability**: mutable (default) / `final` (runtime-immutable) / `cryo` (compile-time constant)

```ems
public final Int constant = 42;
private cryo String API_VERSION = "v1";
```

### Primitives

`Int` (Int64), `Float` (Float64), `Bool`, `Char`, `String`, `Void`, `Any`, `Range`. **No autoconvert** between String and others - always use interpolation `"$(expr)"` or explicit `.toString()`.

### Strings

Double-quoted only. Interpolation via `$(expr)` (NOT `${expr}`). Raw `"a" + "b"` works for String+String concatenation but no other type mixing.

### Control Flow

```ems
if (condition) { ... } else if (other) { ... } else { ... }
while (condition) { ... }
for (i in 1..10) { ... }    // Inclusive range
match value { ... }          // See pattern section
```

### Functions

```ems
public Int square(Int x) {
    return x * x;
}

// Arrow shorthand
public Int double(Int x) -> x * 2;
```

Free functions exist at top level or in namespaces. The `main()` entry point is special: if defined, it's the program entry; if absent, top-level statements run directly.

### Classes

```ems
public class User {
    private String name;
    private Int age;

    public User(String name, Int age) {
        this.name = name;
        this.age = age;
    }

    public String greet() {
        return "Hi, I'm $(this.name)";
    }
}

// Construction: NO 'new' keyword
User u = User("Alice", 30);
```

Empty constructors require parens: `Logger log = Logger();`.

### Inheritance & Interfaces

```ems
public interface Greeter {
    public String greet();
    public default String wave() -> "👋";   // Default method
}

public abstract class Animal {
    public abstract String sound();
}

public class Dog extends Animal implements Greeter {
    @override
    public String sound() {
        return "Woof";
    }

    @override
    public String greet() {
        return "Hi, I bark";
    }
}
```

### Data Classes

```ems
public data class Point(
    @public final Int x,
    @public final Int y
)
```

Auto-generates: constructor, `equals(other)`, `copy(...)` with optional named fields, `to_s`. No body braces needed for pure data classes.

### Lambdas

```ems
// Expression-bodied
(Int x) -> x * 2

// Block-bodied
(Int x) -> {
    Int doubled = x * 2;
    return doubled;
}

// Trailing lambda (Sprint 6)
list.forEach { x -> println(x) }
Fiber.spawn { compute() }

// 'it' for single-arg trailing lambda (Sprint 6, partial)
list.map { it * 2 }
```

### Method References

`::` for everything related to "addressing a member":
```ems
list.map(Int::toString)        // Type::method
list.map(this::process)        // instance::method
List<String> names = users.map(User::getName);
```

### Pattern Matching

```ems
match value {
    0 -> "zero";
    1..10 -> "small";
    is String s -> "string: $(s)";
    User(name, age) if age > 18 -> "adult $(name)";
    null -> "nothing";
    _ -> "other";
}
```

Pattern types: Literal, Range, Type-with-binding, Destructuring (data classes), Guard, Wildcard, Bind, Null, plus `Ok(x)` / `Err(e)` for Result.

### Result Type

Built-in: `Result<T, E>`. Constructors: `Ok(value)`, `Err(error)`. No null.

```ems
public Result<Int, String> parseAge(String s) {
    if (s.length() == 0) {
        return Err("empty");
    }
    return Ok(s.toInt());
}

match parseAge(input) {
    Ok(age)  -> println("Age: $(age)");
    Err(msg) -> println("Failed: $(msg)");
};
```

`Result`, `Ok`, `Err` are reserved names and cannot be redefined.

### Built-in Containers (Sprint 5)

`List<T>`, `Map<K, V>`, `Set<T>` map to Crystal `Array(T)`, `Hash(K, V)` (insertion-order preserving), `Set(T)`.

```ems
List<Int> nums = List();
nums.add(1); nums.add(2); nums.add(3);

Map<String, Int> ages = Map();
ages.put("Alice", 30);

Set<String> tags = Set();
tags.add("urgent");
```

Type args are inferred from the variable's type annotation. Names are reserved.

Available methods (subset): `length`, `isEmpty`, `add/get/set`, `put/remove`, `contains`, `forEach`, `map`, `filter`, `reduce`, `find`, `any`, `all`.

### Namespaces

Default root is `Emerald`. Sub-folders map to sub-namespaces:
- `src/main.ems` → `Emerald::*`
- `src/IO/Logger.ems` → `Emerald::IO::Logger`

Implicit-Use: short names work when unambiguous. On conflict, use FQN or `alias`:
```ems
alias UserModel = MyCompany::Domain::User;
```

### Built-in Free Functions (Sprint 5)

In `Emerald::Math`, `Emerald::IO`, `Emerald::Time`. Implicit-Use makes them callable as `Math::sqrt(x)` etc.

```ems
Math::pi(), Math::sqrt(2.0), Math::pow(b, e), Math::sin/cos/tan, Math::random(), Math::min/max
IO::readFile(path), IO::writeFile(path, content), IO::readLine(), IO::exists(path)
Time::now() // ms epoch, Time::nowSeconds(), Time::sleep(ms)
```

### User-Generics (Sprint 6)

```ems
public class Box<T> {
    private T value;
    public Box(T value) { this.value = value; }
    public T get() { return this.value; }
}

public class Pair<A, B> {
    private A first;
    private B second;
    public Pair(A first, B second) { this.first = first; this.second = second; }
    public A getFirst() { return this.first; }
    public B getSecond() { return this.second; }
}

Box<Int> b = Box(42);                // Type args inferred from variable type
Pair<String, Int> p = Pair("a", 1);
```

### Concurrency (Sprint 6)

Three tiers, identical API:
```ems
Fiber<Int> f = Fiber.spawn { compute() };           // Crystal fiber
Thread<Int> t = Thread.spawn { heavyIO() };         // OS thread
VirtualThread<Int> v = VirtualThread.spawn { ... }; // = Fiber for now, @blocking-aware later

Int result = f.await();
```

```ems
Channel<Int> ch = Channel.new();
ch.send(42);
Int v = ch.receive();
ch.close();

Mutex lock = Mutex.new();
lock.synchronize(() -> {
    // critical section
});
// Or explicit:
lock.lock(); /* ... */ lock.unlock();
```

`Fiber`, `Thread`, `VirtualThread`, `Channel`, `Mutex` are reserved built-in container names.

## Crystal Quirks Already Solved (Don't Re-invent)

- `Object` cannot be in unions or instance vars → use abstract base class
- `Reference` cannot be instance-var type
- `Object?` invalid as field type
- Generic class methods can't have `T.class = String` defaults
- Inline `[] of String` as method arg is parser-ambiguous → assign to var first
- Crystal `/` between Int returns Float, need `//` for integer division
- Multi-line `String::Builder` with multiple `.to_s` crashes → use String.build with single block
- `"#{` in heredoc string with literal `#{ }` triggers Crystal interpolation → use char literals
- Match-expr Object-typed Proc args fail → use `begin..end` with `loop do .. break value end`
- Lambda variable calls need `.call(...)` in Crystal
- Pattern guards must execute AFTER bindings, not in the test condition
- Crystal rescue syntax: `rescue ex : Exception` not just `rescue ex`
- Crystal generics: `class Foo(T)` not `class Foo<T>` - the codegen does this mapping

## Current State of Sprint 6 (last known)

**Fixed in latest zip:**
1. `new` removed from keywords so `Mutex.new()` and `Channel.new()` parse correctly
2. `TypeChecker.@current_type_params` added so `T`/`A`/`B` etc. don't get flagged as undefined types
3. `parse_trailing_lambda` allows last expression without semicolon before `}`
4. Generic `this` type: in `Box<T>`, `this` is now typed as `Emerald::Box<T>` so `this.value` is `T`

**Examples in `examples/`:**
- `01_hello.ems` - works
- `02_generic_box.ems` - was failing on `T` as undefined, should work now
- `03_generic_pair.ems` - same fix
- `04_fiber.ems` - was failing on `}` after `compute()`, should work now
- `05_multi_fiber.ems` - same fix
- `06_channel.ems` - was failing on `new` keyword, should work now
- `07_mutex.ems` - same fix

**Anticipated next bugs (not yet seen):**
1. Crystal-generic class codegen quirks - `class Emerald_Box(T)` with `@value : T` and `def initialize(@value : T)` should be standard but might have edge cases
2. `forall T` syntax in `EmeraldFiber.spawn` self-method might not be valid Crystal
3. Container `it` keyword in `list.map { it * 2 }` is partial - needs proper bidirectional type inference
4. `Mutex.synchronize` with Void-returning lambda might break on Crystal type checking

## Sprint 6 Deferred to Sprint 7

- `it` keyword full support for container ops (needs better type inference)
- `concurrent { ... }` block (structured concurrency)
- `@blocking` annotation for VirtualThread auto-promotion
- Bounded generics: `<T : Comparable>`
- Generic methods independent of class

## Sprint 7+: Macros / Annotations (The Killer Feature)

This is the long-term vision. Annotations like `@Cached`, `@Repository`, `@RestController`, `@Async` should be macros that expand to real code at compile time. This is what makes Emerald different from being "just another typed language."

Example of the target:
```ems
@RestController("/api/auth")
public class AuthController {
    private AuthService service;

    public AuthController(AuthService service) {
        this.service = service;
    }

    @Post("/login")
    @ValidateBody(LoginRequest)
    public HttpResponse login(LoginRequest body) {
        return match this.service::login(body.email, body.password) {
            Ok(token) -> HttpResponse::ok({ "token": token });
            Err(WrongPassword()) -> HttpResponse::unauthorized("Invalid credentials");
            Err(_) -> HttpResponse::serverError("Login failed");
        };
    }
}
```

`@RestController("/api/auth")` would register the class with an HTTP router via compile-time codegen. `@Post("/login")` would do route registration plus JSON body deserialization. `@ValidateBody` would generate validation code from the type. All resolved at compile time, no runtime reflection.

For Sprint 7, we'd start with a simpler macro foundation - probably:
1. `@inject` for dependency injection (constructor wiring)
2. `@override` formalized (currently parsed, not enforced)
3. `@blocking` for VirtualThread promotion
4. `@deprecated` with compile-time warnings

Then build up to the full quasi-quote / AST-manipulation macro system.

## How User Likes to Work

The user (SyntaxJason):
- German native speaker, prefers fast pace, less prose more code
- Linux developer with Crystal 1.20.0 native (not in WSL)
- Working directory: `~/Schreibtisch/Emerald/compiler`
- Commits each working sprint as `git commit -m "sprint N working"`
- Asks for `ehrlichkeit` (honesty) - prefers being told when something is a bad idea
- Iteration loop: Claude builds zip, user runs `shards build` and tests examples, sends back errors

User cannot have Crystal called from the assistant's sandbox (network/binary restrictions), so the AI cannot test compiles itself. Iteration is sequential through the user.

## Build & Test Workflow

```bash
cd compiler
shards build
./bin/emeraldc build ../examples/01_hello.ems -o /tmp/test && /tmp/test
```

Build the zip:
```bash
cd /home/claude
rm -f emerald-sprint-N.zip
zip -r emerald-sprint-N.zip emerald-sprint-N -q
cp emerald-sprint-N.zip /mnt/user-data/outputs/
```

## Reserved Names (Cannot Be Redefined)

- `Result`, `Ok`, `Err` (Result type)
- `List`, `Map`, `Set` (built-in containers)
- `Fiber`, `Thread`, `VirtualThread`, `Channel`, `Mutex` (concurrency)
