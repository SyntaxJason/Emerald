# Emerald Compiler – Sprint 6

Sprint 6 bringt User-Generics + Concurrency.

## Was Sprint 6 hinzufügt

### User-Generics

Eigene Klassen können generische Type-Parameter haben:
```
public class Box<T> {
    private T value;
    public Box(T value) { this.value = value; }
    public T get() { return this.value; }
}

Box<Int> b = Box(42);
```

Multiple Type-Params:
```
public class Pair<A, B> {
    private A first;
    private B second;
    ...
}
```

Type-Args werden aus dem Variable-Type inferiert. `Box(42)` mit `Box<Int> b` als Annotation ergibt `Box<Int>`.

### Concurrency

Drei Tiers, gleiche API via `<Type>.spawn { ... }`:
```
Fiber<Int> f = Fiber.spawn { compute() };
Thread<Int> t = Thread.spawn { heavy_io() };
VirtualThread<Int> v = VirtualThread.spawn { mixed() };

Int result = f.await();
```

- **`Fiber`** mappt zu Crystal's nativen Fibers (cooperative)
- **`Thread`** mappt zu Crystal's `Thread` (echte OS-Threads)
- **`VirtualThread`** für Sprint 6 identisch zu Fiber, später mit `@blocking`-Auto-Detection

### Channels

```
Channel<Int> ch = Channel.new();
ch.send(42);
Int v = ch.receive();
ch.close();
```

### Mutex

```
Mutex lock = Mutex.new();
lock.synchronize(() -> {
    // critical section
});
```

Oder explizit:
```
lock.lock();
// ...
lock.unlock();
```

### Trailing-Lambda-Syntax

```
Fiber.spawn { compute() }
mutex.synchronize { ... }
```

`{ ... }` direkt nach Method-Call ohne Parens wird als Lambda-Argument durchgereicht.

## Was noch nicht geht

- **`it`-Keyword** für Container-Operationen (`list.map { it * 2 }`) – braucht bessere Type-Inferenz
- **`concurrent { }`-Block** – kommt in Sprint 7 mit Macros
- **`@blocking`-Annotation** – kommt in Sprint 7 mit Macros
- **Bounded Generics** (`<T : Comparable>`)
- **Generic Methods** (Methoden mit eigenen Type-Params unabhängig von Class)

## Beispiele

```bash
cd compiler && shards build
./bin/emeraldc build ../examples/01_hello.ems         -o /tmp/h    && /tmp/h
./bin/emeraldc build ../examples/02_generic_box.ems   -o /tmp/box  && /tmp/box
./bin/emeraldc build ../examples/03_generic_pair.ems  -o /tmp/pair && /tmp/pair
./bin/emeraldc build ../examples/04_fiber.ems         -o /tmp/fib  && /tmp/fib
./bin/emeraldc build ../examples/05_multi_fiber.ems   -o /tmp/mf   && /tmp/mf
./bin/emeraldc build ../examples/06_channel.ems       -o /tmp/ch   && /tmp/ch
./bin/emeraldc build ../examples/07_mutex.ems         -o /tmp/mtx  && /tmp/mtx
```
