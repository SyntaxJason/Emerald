# Emerald

Emerald is a statically typed, Java-inspired programming language that compiles to native code through LLVM. It pairs Java-like structure with Crystal-like ergonomics and compile-time macros, and it ships with its own memory model, **HyperAlloc Flow**, so programs run without an external garbage collector.

The Emerald compiler is written in Emerald. A small Crystal bootstrap compiler builds the first stage, and from there Emerald builds itself.

```ems
public class Greeter {
    private String name;

    public Greeter(String name) {
        this.name = name;
    }

    public String greet() {
        return "Hello, $(this.name)!";
    }
}

main() {
    Greeter greeter = Greeter("Emerald");
    println(greeter.greet());
}
```

## Highlights

- **Java-like structure, low ceremony**: classes, interfaces with default methods, abstract classes, generics, namespaces, constructors, visibility modifiers, annotations, string interpolation (`$(expr)`), ranges and lambdas.
- **Native code through LLVM**: executables, object files, assembly or LLVM IR for `linux-x64`, `linux-arm64` and `windows-x64`.
- **Self-hosted**: `emerald-compiler/` contains the full compiler (lexer, parser, binder, macro interpreter, HyperAlloc Flow analysis, LLVM backend) written in `.ems`.
- **HyperAlloc Flow**: the compiler analyses how every allocation is used and picks a strategy for it. The runtime is built in and needs no external GC library.
- **Compile-time macros**: macros are written like annotations, can rewrite methods, classes and fields, and support `quote` / `unquote` templates.
- **Concurrency**: fibers with `await`, `@Async` methods and `@Synchronized` methods.
- **Standard library**: collections, I/O, files and directories, text, JSON, math, time, random, processes, TCP/UDP, HTTP, WebSocket, native UI and LLVM bindings.
- **Prism**: a package manager with a registry and GitHub dependencies.
- **Tooling**: a VS Code extension with syntax highlighting, snippets and the Emerald Dark theme, plus a graphical installer.

## A quick tour

### Classes, inheritance and annotations

```ems
public abstract class Animal {
    public abstract String sound();
}

public class Dog extends Animal {
    @Override
    public String sound() {
        return "Woof";
    }
}

main() {
    Dog d = Dog();
    println("Dog says: $(d.sound())");
}
```

### Generics and interfaces

```ems
public interface IOption<T> {
    public Bool isSome();
    public T unwrapOr(T fallback);
}

public class Some<T> implements IOption<T> {
    private T value;

    public Some(T value) {
        this.value = value;
    }

    public Bool isSome() {
        return true;
    }

    public T unwrapOr(T fallback) {
        return this.value;
    }
}
```

### Collections and lambdas

```ems
use Std::Collections::ArrayList;
use Std::Collections::HashMap;
use Std::Collections::IList;
use Std::Collections::IMap;

main() {
    IList<String> names = ArrayList();
    names.add("Ada");
    names.add("Grace");
    names.forEach((name) -> println(name));

    IMap<String, Int> ages = HashMap();
    ages.put("Ada", 36);
    println(ages.getOr("Missing", 0).toString());
}
```

### Fibers and synchronization

```ems
public class Counter {
    private Int count;

    public Counter() {
        this.count = 0;
    }

    @Synchronized
    public Void increment() {
        this.count = this.count + 1;
    }

    @Synchronized
    public Int value() {
        return this.count;
    }
}

main() {
    Counter counter = Counter();

    Fiber<Void> a = Fiber.spawn {
        for (i in 1..1000) {
            counter.increment();
        }
    };
    Fiber<Void> b = Fiber.spawn {
        for (j in 1..1000) {
            counter.increment();
        }
    };

    a.await();
    b.await();
    println("Final count: $(counter.value())");
}
```

`@Async` turns a method into one that returns a `Fiber<T>`:

```ems
public class Computation {
    @Async
    public Int slowSquare(Int x) {
        Time::sleep(50);
        return x * x;
    }
}

main() {
    Computation comp = Computation();
    Fiber<Int> a = comp.slowSquare(5);
    Fiber<Int> b = comp.slowSquare(10);
    println("Sum of squares: $(a.await() + b.await())");
}
```

### Macros

Macros look like annotations but run at compile time and can rewrite the code they are attached to.

```ems
macro Logged on Method {
    StatementAST entry = Stmt::expr(
        Expr::call("println", [Expr::str("→ " + method.name)])
    );
    StatementAST exit = Stmt::expr(
        Expr::call("println", [Expr::str("← " + method.name)])
    );
    method.body.prepend(entry);
    method.body.append(exit);
}

public class Calculator {
    @Logged
    public Int square(Int x) {
        return x * x;
    }
}
```

Code templates use `quote` with a kind (`expr`, `stmt`, `block`, `method`, `field`) and `$(...)` to splice values in:

```ems
ExpressionAST message = Expr::str("hello");

StatementAST stmt = quote stmt {
    println($(message));
};
```

### Namespaces and imports

Namespaces and imports use `::`. Aliases resolve clashes between classes that share a simple name.

```ems
namespace App::Auth;

public class User {
}
```

```ems
use App::Auth::User as AuthUser;
```

More than 200 runnable programs live in [`examples/`](examples), from language basics up to memory-model, networking and UI scenarios.

## HyperAlloc Flow

HyperAlloc Flow is Emerald's memory model. During compilation, the analyzer follows each allocation through the program (escape, ownership and lifetime analysis) and assigns it one of these strategies:

| Strategy | Used when |
| --- | --- |
| **Folded** | small values and read-only method calls can be folded away entirely |
| **Inline** | value-like objects can be copied and kept inline |
| **Local** | the object stays inside its scope and is released with it |
| **Shard** | objects are created repeatedly in a scope, such as a loop body |
| **Pool** | objects can reuse the same slots |
| **Root** | objects escape their scope, for example by being returned or stored |
| **Bond** | objects have several owners, including cyclic ones, with automatic cycle protection |

The runtime side (regions, ownership and allocator state) lives in [`runtime/`](runtime). The compiler flags below make the decisions visible:

```bash
emerald-compiler build app.ems -o app --explain-hyperalloc-flow    # print every allocation decision
emerald-compiler build app.ems -o app --hyperalloc-flow-strict     # reject unresolved fallbacks
emerald-compiler analyze app.ems --ram                             # estimate memory use
```

Strict mode still allows allocations that are deliberately `Root`.

## Getting started

### Requirements

- Linux or Windows. Both are first-class targets; macOS is not supported yet.
- A C compiler / linker on `PATH`, `clang` recommended. Set `EMERALD_CC` (for example `clang` or `clang.exe`) if yours is not found.
- To build Emerald from source: [Crystal](https://crystal-lang.org) with `shards` for the bootstrap compiler, plus LLVM and clang.

### Build from source

```bash
git clone https://github.com/SyntaxJason/Emerald.git
cd Emerald

./emerald.sh bootstrap   # Crystal bootstrap compiler, then the Emerald compiler
./emerald.sh selfhost    # Stage 1, 2 and 3: Emerald compiling itself
```

`./emerald.sh help` lists every command. Selfhost runs inside a memory-capped Docker container by default (8 GB, see `docker/Dockerfile.selfhost`); pass `--no-sandbox` to run directly on the host.

### Compile and run a program

```bash
emerald-compiler build hello.ems -o hello
./hello
```

`emerald-compiler hello.ems [output]` is a shorthand for the same thing.

| Option | Meaning |
| --- | --- |
| `-o <path>` | output base path (Windows targets get `.exe` automatically) |
| `--emit <mode>` | `exe`, `obj`, `asm` or `llvm-ir` |
| `--emit-ir` / `--no-ir` | also write, or never write, the LLVM IR |
| `--keep-temps` | keep temporary `.o` / `.ll` build files |
| `--target <target>` | `native`, `linux-x64`, `linux-arm64`, `windows-x64` |
| `--cc <path>` | override the C compiler / linker command |
| `--sysroot <path>` | pass `--sysroot` to the runtime compile and link steps |
| `--explain-hyperalloc-flow` | print HyperAlloc Flow allocation decisions |
| `--hyperalloc-flow-strict` | reject unresolved Flow fallbacks |

The compiler finds its standard library through `EMERALD_HOME` and `EMERALD_STDLIB`.

### Installer and release packages

The `Emerald Release` GitHub Actions workflow builds a Linux `.tar.gz`, a Windows `.zip` and a graphical installer. Each package contains the compiler, `stdlib/`, `runtime/` and `emerald-compiler/`. The installer sets up `EMERALD_HOME`, `EMERALD_STDLIB` and `PATH` for the current user; see [`compiler/tools/installer`](compiler/tools/installer).

## Prism package manager

Prism is written in Emerald and lives in [`emerald-compiler/src/emerald/prism`](emerald-compiler/src/emerald/prism).

```bash
./emerald.sh prism        # build Prism

prism init my-app         # create prism.toml
prism build
prism run
prism install             # fetch dependencies
prism update
prism lock
prism clean
prism info
```

Projects are described by `prism.toml` (package, build, registry, dependencies and assets). Dependencies come from the registry (`https://prism.emerald-lang.eu` by default) or straight from GitHub:

```toml
[dependencies]
my-lib = "github:owner/repo@ref"
```

## Standard library

The standard library is interface-first: every major type has an `I…` interface and a default implementation, and behaviour is written as ordinary Emerald code rather than compiler magic.

| Namespace | Contents |
| --- | --- |
| `Std::Collections` | `ArrayList`, `Deque`, `Queue`, `Stack`, `PriorityQueue`, `HashMap`, `HashSet`, iterators and the `IList` / `IMap` / `ISet` interfaces |
| `Std::Compare` | `IComparable`, `IComparator`, `IEquatable`, natural and reverse comparators |
| `Std::Data` | `Box`, `MutableBox`, `Pair`, `Triple`, `KeyValuePair`, `IntRange`, `IndexedValue` |
| `Std::Functional` | `IFunction`, `IPredicate`, `IConsumer`, `ISupplier`, `IBinaryOperator`, `IReducer` and friends |
| `Std::Option`, `Std::Result` | `Some` / `None`, `Success` / `Failure` |
| `Std::Io` | `Console`, `File`, `Directory`, `FileInfo`, `Files`, `Directories`, `FileSystem`, text readers and writers |
| `Std::Text` | `StringBuilder`, `Strings` |
| `Std::Json` | `JsonObject`, `JsonArray`, `JsonString`, `JsonNumber`, `JsonBool`, `JsonNull` |
| `Std::Math`, `Std::Random`, `Std::Time` | math, random numbers, `Clock`, `Duration`, `OffsetDateTime` |
| `Std::Env`, `Std::System`, `Std::Process` | environment, platform information, processes |
| `Std::Net`, `Std::Http`, `Std::WebSocket` | `Endpoint`, `Uri`, TCP and UDP, HTTP client / request / response, WebSocket sessions |
| `Std::Ui` | native UI windows and applications, `@EmHtml` views with `@UiBind` / `@UiAction` |
| `Std::Llvm` | LLVM context, module, builder and native backend bindings used by the compiler itself |

## Editor support

[`compiler/tools/vscode-emerald`](compiler/tools/vscode-emerald) contains the VS Code extension for `.ems` files: TextMate highlighting, snippets (classes, interfaces, Option, Result, collections, console, HTTP, TCP), bracket and comment configuration and the **Emerald Dark** theme. Install the bundled `.vsix`, then pick the theme under *Preferences: Color Theme*.

## Repository layout

```txt
emerald-compiler/   the Emerald compiler and Prism, written in Emerald (.ems)
compiler/           Crystal bootstrap compiler (emeraldc), installer and VS Code extension
stdlib/             the Emerald standard library
runtime/            C runtime: HyperAlloc Flow, lists, strings, numbers, I/O, network, UI, LLVM bridge
examples/           200+ runnable example programs
tests/              selfhost, runtime and performance tests
demos/              memory and cross-language comparison demos
scripts/            profile-guided optimization training scripts
docker/             sandbox image for the selfhost run
emerald.sh          build, test and selfhost driver
```

## Testing

```bash
./emerald.sh positive                    # run every program in examples/
./emerald.sh selfhost                    # Stage 1 -> 2 -> 3 selfhost gate
tests/runtime/run-sandboxed.sh           # C runtime tests inside a capped container
```

`tests/selfhost/` also covers parser parity, API parity, language features, nested projects and HyperAlloc Flow memory behaviour. Compiler and selfhost runs are meant to be sandboxed so a memory regression stops the container and not your machine.
