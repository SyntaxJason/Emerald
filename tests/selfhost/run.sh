#!/usr/bin/env bash

set -e
set -u
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESULTS="$ROOT/test-results-selfhost"
LOGS="$RESULTS/logs"
STAGES="$RESULTS/stages"
VERIFY="$RESULTS/verify"
STAGE0="${EMERALD_STAGE0:-$ROOT/compiler/bin/emeraldc}"
STAGE1="${EMERALD_STAGE1:-$ROOT/emerald-compiler/emerald-compiler}"
BUILD=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build)
      BUILD=false
      shift
      ;;
    *)
      echo "Unknown selfhost option: $1"
      exit 2
      ;;
  esac
done

section() {
  echo
  echo "================================================================================"
  echo "$1"
  echo "================================================================================"
  echo
}

fail() {
  echo "[Selfhost] FAIL: $1"
  exit "${2:-1}"
}

find_llvm() {
  if [[ -n "${EMERALD_LLVM_LIBRARY:-}" ]]; then
    export EMERALD_LLVM_LIB_DIR="${EMERALD_LLVM_LIB_DIR:-}"
    return
  fi

  if command -v llvm-config >/dev/null 2>&1; then
    local libs
    EMERALD_LLVM_LIB_DIR="$(llvm-config --libdir)"
    libs="$(llvm-config --link-shared --libs 2>/dev/null || llvm-config --libs)"
    EMERALD_LLVM_LIBRARY="$(sed -n 's/.*-l\([^ ]*LLVM[^ ]*\).*/\1/p' <<< "$libs" | head -1)"

    if [[ -z "$EMERALD_LLVM_LIBRARY" ]]; then
      EMERALD_LLVM_LIBRARY="LLVM"
    fi

    export EMERALD_LLVM_LIB_DIR EMERALD_LLVM_LIBRARY
    return
  fi

  local library_path
  library_path="$(ldconfig -p 2>/dev/null | awk '/libLLVM(-[0-9]+)?\.so/{print $NF; exit}')"

  if [[ -z "$library_path" ]]; then
    fail "LLVM shared library not found. Install LLVM or set EMERALD_LLVM_LIB_DIR and EMERALD_LLVM_LIBRARY."
  fi

  EMERALD_LLVM_LIB_DIR="$(dirname "$library_path")"
  local file_name
  file_name="$(basename "$library_path")"

  if [[ "$file_name" =~ ^lib(LLVM-[0-9]+)\.so ]]; then
    EMERALD_LLVM_LIBRARY="${BASH_REMATCH[1]}"
  elif [[ "$file_name" == libLLVM.so ]]; then
    EMERALD_LLVM_LIBRARY="LLVM"
  elif [[ "$file_name" =~ ^libLLVM\.so\.[0-9]+ ]]; then
    EMERALD_LLVM_LIBRARY=":$file_name"
  else
    fail "Could not derive LLVM linker name from: $library_path"
  fi

  export EMERALD_LLVM_LIB_DIR EMERALD_LLVM_LIBRARY
}

run_logged() {
  local title="$1"
  local log="$2"
  shift 2

  section "$title"
  : > "$log"
  printf '%q ' "$@" | tee -a "$log"
  echo | tee -a "$log"
  set +e
  "$@" 2>&1 | tee -a "$log"
  local status=${PIPESTATUS[0]}
  set -e

  if [[ "$status" -ne 0 ]]; then
    fail "$title failed. Log: $log" "$status"
  fi
}

find_llvm
export EMERALD_HOME="$ROOT"
export EMERALD_PLAIN_ERRORS=1
# Use normal deterministic releases for Stage 2/3. The old leak-allocation
# compatibility mode remains available explicitly with
# HYPERALLOC_FLOW_BOOTSTRAP=1 for diagnosing historical compiler snapshots.
export HYPERALLOC_FLOW_BOOTSTRAP="${HYPERALLOC_FLOW_BOOTSTRAP:-0}"

FLOW_ANALYSIS_REVISION="unknown"

if [[ -f "$ROOT/.hyperalloc-flow-revision" ]]; then
  FLOW_ANALYSIS_REVISION="$(tr -d '\r\n' < "$ROOT/.hyperalloc-flow-revision")"
fi

echo "[Selfhost] Flow analysis revision: $FLOW_ANALYSIS_REVISION"

section "LLVM prelude coverage"
LLVM_PRELUDE="$ROOT/stdlib/llvm/LlvmPrelude.ems"
[[ -f "$LLVM_PRELUDE" ]] || fail "LLVM prelude missing: $LLVM_PRELUDE"
LLVM_CLASS_COUNT=0

for llvm_source in "$ROOT"/stdlib/llvm/*.ems; do
  llvm_class="$(sed -n 's/^public class \([A-Za-z0-9_]*\).*/\1/p' "$llvm_source" | head -1)"

  if [[ -z "$llvm_class" || "$llvm_class" == "LlvmPrelude" ]]; then
    continue
  fi

  grep -Fxq "use Std::Llvm::$llvm_class;" "$LLVM_PRELUDE" || fail "LlvmPrelude does not load Std::Llvm::$llvm_class"
  LLVM_CLASS_COUNT=$((LLVM_CLASS_COUNT + 1))
done

[[ "$LLVM_CLASS_COUNT" -gt 0 ]] || fail "LlvmPrelude coverage found no LLVM classes"
echo "[Selfhost] OK: LlvmPrelude loads $LLVM_CLASS_COUNT LLVM classes"

section "Compiler prelude coverage"
COMPILER_PRELUDE="$ROOT/emerald-compiler/src/emerald/compiler/CompilerPrelude.ems"
[[ -f "$COMPILER_PRELUDE" ]] || fail "Compiler prelude missing: $COMPILER_PRELUDE"
COMPILER_CLASS_COUNT=0

while IFS= read -r compiler_source; do
  compiler_file="$(basename "$compiler_source")"

  if [[ "$compiler_file" == "CompilerPrelude.ems" ]]; then
    continue
  fi

  compiler_namespace="$(sed -n 's/^namespace \([^;]*\);/\1/p' "$compiler_source" | head -1)"
  compiler_class="${compiler_file%.ems}"
  [[ -n "$compiler_namespace" ]] || fail "Compiler source has no namespace: $compiler_source"
  grep -Fxq "use $compiler_namespace::$compiler_class;" "$COMPILER_PRELUDE" || fail "CompilerPrelude does not load $compiler_namespace::$compiler_class"
  COMPILER_CLASS_COUNT=$((COMPILER_CLASS_COUNT + 1))
done < <(find "$ROOT/emerald-compiler/src/emerald/compiler" -type f -name '*.ems' | sort)

[[ "$COMPILER_CLASS_COUNT" -gt 0 ]] || fail "CompilerPrelude coverage found no compiler classes"
echo "[Selfhost] OK: CompilerPrelude loads $COMPILER_CLASS_COUNT compiler classes"

rm -rf "$RESULTS"
mkdir -p "$LOGS" "$STAGES/stage2" "$STAGES/stage3" "$VERIFY"

section "LLVM bridge smoke test"
CC_COMMAND="${CC:-clang}"
"$CC_COMMAND" -std=c11 -O2 -DEMERALD_RUNTIME_ENABLE_LLVM=1 -I"$ROOT" "$ROOT/runtime/emerald_runtime.c" "$ROOT/tests/selfhost/llvm_bridge_smoke.c" -L"$EMERALD_LLVM_LIB_DIR" -l"$EMERALD_LLVM_LIBRARY" -ldl -o "$VERIFY/llvm-bridge-smoke"
"$VERIFY/llvm-bridge-smoke"
set +e
"/tmp/emerald-selfhost-bridge-program"
BRIDGE_EXIT=$?
set -e
[[ "$BRIDGE_EXIT" -eq 42 ]] || fail "LLVM bridge program returned $BRIDGE_EXIT instead of 42"
echo "[Selfhost] OK: LLVM bridge emitted a native program returning 42"

section "Native String runtime smoke test"
"$CC_COMMAND" -std=c11 -O2 -Wall -Wextra -Werror -I"$ROOT" "$ROOT/runtime/emerald_runtime.c" "$ROOT/tests/selfhost/string_runtime_smoke.c" -ldl -o "$VERIFY/string-runtime-smoke"
"$VERIFY/string-runtime-smoke"
echo "[Selfhost] OK: native String split, trim, case conversion, parsing, character checks, replace, substring and indexOf return expected values"

if [[ "$BUILD" == true ]]; then
  if command -v shards >/dev/null 2>&1; then
    run_logged "Build Stage 0" "$LOGS/stage0.log" bash -lc "cd '$ROOT/compiler' && shards build emeraldc"
  elif command -v crystal >/dev/null 2>&1; then
    run_logged "Build Stage 0" "$LOGS/stage0.log" bash -lc "cd '$ROOT/compiler' && crystal build src/emeraldc.cr -o bin/emeraldc"
  else
    fail "Crystal or Shards is required to rebuild Stage 0"
  fi

  STAGE0="$ROOT/compiler/bin/emeraldc"
  run_logged "Build Stage 1 with Stage 0" "$LOGS/stage1.log" "$STAGE0" build "$ROOT/emerald-compiler/src/Main.ems" -o "$STAGE1"
fi

[[ -x "$STAGE1" ]] || fail "Stage 1 compiler not executable: $STAGE1"

LLVM_API_SMOKE="$VERIFY/llvm-api-smoke"
run_logged "Build LLVM API smoke with Stage 1" "$LOGS/llvm-api-smoke-build.log" "$STAGE1" build "$ROOT/tests/selfhost/llvm_api_smoke.ems" -o "$LLVM_API_SMOKE"
run_logged "Run LLVM API smoke" "$LOGS/llvm-api-smoke-run.log" bash -lc "cd '$VERIFY' && if command -v stdbuf >/dev/null 2>&1; then stdbuf -o0 -e0 './llvm-api-smoke'; else './llvm-api-smoke'; fi"
grep -Fxq "llvm-api-smoke-ok" "$LOGS/llvm-api-smoke-run.log" || fail "Stage 1 LLVM API smoke did not report success"
set +e
"$VERIFY/llvm-api-child" >/dev/null 2>&1
LLVM_API_EXIT=$?
set -e
[[ "$LLVM_API_EXIT" -eq 42 ]] || fail "Stage 1 LLVM API child returned $LLVM_API_EXIT instead of 42"
echo "[Selfhost] OK: Stage 1 emits and links LLVM through the native bridge"

NESTED_PROJECT_SMOKE="$VERIFY/nested-project-smoke"
run_logged "Build nested project loader smoke with Stage 1" "$LOGS/nested-project-build.log" "$STAGE1" build "$ROOT/tests/selfhost/nested_project/src/Main.ems" -o "$NESTED_PROJECT_SMOKE"
run_logged "Run nested project loader smoke" "$LOGS/nested-project-run.log" "$NESTED_PROJECT_SMOKE"
grep -Fxq "42" "$LOGS/nested-project-run.log" || fail "Stage 1 nested project loader smoke did not return 42"
echo "[Selfhost] OK: Stage 1 resolves logical namespaces across physical source folders"

PARSER_PARITY_SMOKE="$VERIFY/parser-parity-smoke"
run_logged "Build parser parity smoke with Stage 1" "$LOGS/parser-parity-build.log" "$STAGE1" build "$ROOT/tests/selfhost/parser_parity/Main.ems" -o "$PARSER_PARITY_SMOKE"
run_logged "Run parser parity smoke" "$LOGS/parser-parity-run.log" "$PARSER_PARITY_SMOKE"
grep -Fxq "42" "$LOGS/parser-parity-run.log" || fail "Stage 1 parser parity smoke did not return 42"
echo "[Selfhost] OK: Stage 1 matches parser symbols and selfhost-critical String builtins"

API_PARITY_SMOKE="$VERIFY/api-parity-smoke"
run_logged "Build native API parity smoke with Stage 1" "$LOGS/api-parity-build.log" "$STAGE1" build "$ROOT/tests/selfhost/api_parity/Main.ems" -o "$API_PARITY_SMOKE"
run_logged "Run native API parity smoke" "$LOGS/api-parity-run.log" "$API_PARITY_SMOKE" emerald-selfhost 42
grep -Fxq "42" "$LOGS/api-parity-run.log" || fail "Stage 1 native API parity smoke did not return 42"
echo "[Selfhost] OK: Stage 1 supports selfhost String, Char, Process and overloaded constructor APIs"

run_logged "Flow temporary memory regression with Stage 1" "$LOGS/flow-memory-stage1.log" bash "$ROOT/tests/selfhost/flow_memory/run.sh" "$STAGE1" "$VERIFY/flow-memory-stage1"
run_logged "Language regressions with Stage 1" "$LOGS/language-stage1.log" bash "$ROOT/tests/selfhost/language_features/run.sh" "$STAGE1" "$VERIFY/language-stage1"
grep -Fxq "flow-memory-ok" "$LOGS/flow-memory-stage1.log" || fail "Stage 1 Flow memory regression did not report success"

STAGE2="$STAGES/stage2/emerald-compiler"
STAGE3="$STAGES/stage3/emerald-compiler"

run_logged "Build Stage 2 with Stage 1" "$LOGS/stage2.log" env "HYPERALLOC_FLOW_ANALYSIS_REVISION=$FLOW_ANALYSIS_REVISION" "$STAGE1" build "$ROOT/emerald-compiler/src/Main.ems" -o "$STAGE2" --emit-ir
[[ -x "$STAGE2" ]] || fail "Stage 2 compiler was not produced"

PARITY_BASE="$VERIFY/compiler-bootstrap-parity"
run_logged "Emit compiler IR with Stage 1" "$LOGS/stage1-parity-ir.log" "$STAGE1" build "$ROOT/emerald-compiler/src/Main.ems" -o "$PARITY_BASE" --emit llvm-ir
cp "$PARITY_BASE.ll" "$VERIFY/stage1-compiler.ll"
run_logged "Emit compiler IR with Stage 2" "$LOGS/stage2-parity-ir.log" "$STAGE2" build "$ROOT/emerald-compiler/src/Main.ems" -o "$PARITY_BASE" --emit llvm-ir
cp "$PARITY_BASE.ll" "$VERIFY/stage2-parity-compiler.ll"

if ! cmp -s "$VERIFY/stage1-compiler.ll" "$VERIFY/stage2-parity-compiler.ll"; then
  diff -u "$VERIFY/stage1-compiler.ll" "$VERIFY/stage2-parity-compiler.ll" > "$VERIFY/bootstrap-ir.diff" || true
  fail "Stage 1 and Stage 2 compiler IR differs. Diff: $VERIFY/bootstrap-ir.diff"
fi

echo "[Selfhost] OK: Stage 1 and native Stage 2 emit identical compiler IR"

run_logged "Build Stage 3 with Stage 2" "$LOGS/stage3.log" "$STAGE2" build "$ROOT/emerald-compiler/src/Main.ems" -o "$STAGE3" --emit-ir
[[ -x "$STAGE3" ]] || fail "Stage 3 compiler was not produced"

run_logged "Stage 2 smoke build" "$LOGS/stage2-smoke.log" "$STAGE2" build "$ROOT/examples/58_emerald_compiler_hello.ems" -o "$VERIFY/stage2-smoke"
run_logged "Stage 3 smoke build" "$LOGS/stage3-smoke.log" "$STAGE3" build "$ROOT/examples/58_emerald_compiler_hello.ems" -o "$VERIFY/stage3-smoke"

"$VERIFY/stage2-smoke" > "$VERIFY/stage2-smoke.out"
"$VERIFY/stage3-smoke" > "$VERIFY/stage3-smoke.out"
cmp -s "$VERIFY/stage2-smoke.out" "$VERIFY/stage3-smoke.out" || fail "Stage 2 and Stage 3 smoke output differs"

echo "[Selfhost] OK: Stage 2 and Stage 3 produce identical smoke output"

run_logged "Flow temporary memory regression with Stage 2" "$LOGS/flow-memory-stage2.log" bash "$ROOT/tests/selfhost/flow_memory/run.sh" "$STAGE2" "$VERIFY/flow-memory-stage2"
run_logged "Flow temporary memory regression with Stage 3" "$LOGS/flow-memory-stage3.log" bash "$ROOT/tests/selfhost/flow_memory/run.sh" "$STAGE3" "$VERIFY/flow-memory-stage3"
run_logged "Language regressions with Stage 2" "$LOGS/language-stage2.log" bash "$ROOT/tests/selfhost/language_features/run.sh" "$STAGE2" "$VERIFY/language-stage2"
run_logged "Language regressions with Stage 3" "$LOGS/language-stage3.log" bash "$ROOT/tests/selfhost/language_features/run.sh" "$STAGE3" "$VERIFY/language-stage3"

IR_BASE="$VERIFY/compiler-fixed-point"
run_logged "Emit compiler IR with Stage 2" "$LOGS/stage2-ir.log" "$STAGE2" build "$ROOT/emerald-compiler/src/Main.ems" -o "$IR_BASE" --emit llvm-ir
cp "$IR_BASE.ll" "$VERIFY/stage2-compiler.ll"
run_logged "Emit compiler IR with Stage 3" "$LOGS/stage3-ir.log" "$STAGE3" build "$ROOT/emerald-compiler/src/Main.ems" -o "$IR_BASE" --emit llvm-ir
cp "$IR_BASE.ll" "$VERIFY/stage3-compiler.ll"

if ! cmp -s "$VERIFY/stage2-compiler.ll" "$VERIFY/stage3-compiler.ll"; then
  diff -u "$VERIFY/stage2-compiler.ll" "$VERIFY/stage3-compiler.ll" > "$VERIFY/compiler-ir.diff" || true
  fail "Stage 2 and Stage 3 compiler IR differs. Diff: $VERIFY/compiler-ir.diff"
fi

cat > "$RESULTS/summary.txt" <<SUMMARY
Emerald selfhost gate passed
============================
Stage 1: $STAGE1
Stage 2: $STAGE2
Stage 3: $STAGE3
LLVM library: $EMERALD_LLVM_LIB_DIR/lib$EMERALD_LLVM_LIBRARY
Bootstrap compiler IR parity: identical
Native compiler IR fixed point: identical
Smoke behavior: identical
SUMMARY

section "Emerald selfhost gate"
cat "$RESULTS/summary.txt"
echo
echo "OK: Emerald compiles itself through Stage 3"
