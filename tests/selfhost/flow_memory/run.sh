#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
COMPILER="$1"
OUTPUT="$2"
mkdir -p "$(dirname "$OUTPUT")"

build_checked() {
    local source="$1" output="$2"
    "$COMPILER" build "$source" -o "$output" --emit llvm-ir
    # Instrument both generated LLVM code and the Runtime; the test checks live
    # allocations before shutdown as well as the lifetime of shared borrowed data.
    clang -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all \
        -fno-omit-frame-pointer "$output.ll" "$ROOT/tests/selfhost/flow_memory/runtime_check.c" \
        -ldl -o "$output"
}

build_checked "$ROOT/tests/selfhost/flow_memory/Main.ems" "$OUTPUT"
# Ownership soundness (interface summaries, callee-adopted caller Roots) and
# temporary leaks (mixed String returns, constructor temporaries, split,
# iterators, native results). Must stay ASan-clean with zero live allocations.
build_checked "$ROOT/tests/selfhost/flow_memory/Ownership.ems" "$OUTPUT-ownership"
ASAN_OPTIONS=detect_leaks=1 "$OUTPUT-ownership" | grep -Fx 'flow-ownership-ok'
# --explain-hyperalloc-flow prints the report after emission; the report must outlive
# the emitter context that adopted it.
"$COMPILER" build "$ROOT/tests/selfhost/flow_memory/Ownership.ems" -o "$OUTPUT-explain" --explain-hyperalloc-flow > "$OUTPUT-explain.log" 2>&1
grep -Fq 'HyperAlloc Flow Report' "$OUTPUT-explain.log"
grep -Fq 'Owned String return copies:' "$OUTPUT-explain.log"
ASAN_OPTIONS=detect_leaks=1 "$OUTPUT"
# Virtual dispatch: Flow decisions at calls to overridden methods must cover
# every override (stack arguments kept by an override, temporaries, results).
"$COMPILER" build "$ROOT/tests/selfhost/flow_memory/VirtualDispatch.ems" -o "$OUTPUT-virtual" --emit llvm-ir
clang -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all \
    -fno-omit-frame-pointer "$OUTPUT-virtual.ll" "$ROOT/tests/selfhost/flow_memory/runtime_check.c" \
    -ldl -o "$OUTPUT-virtual"
ASAN_OPTIONS=detect_leaks=1:detect_stack_use_after_return=1 "$OUTPUT-virtual" > "$OUTPUT-virtual.actual"
printf '77\n88\nflow-virtual-ok\n' | diff -u - "$OUTPUT-virtual.actual"
