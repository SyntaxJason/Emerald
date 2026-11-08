#!/usr/bin/env bash

set -u
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PATCH_DIR="$ROOT/patches"
APPLIED_PATCH_DIR="$PATCH_DIR/applied"
PATCH_RESULTS_DIR="$ROOT/patch-results"
PATCH_LOG="$PATCH_RESULTS_DIR/apply-patches.log"

EXAMPLES_DIR="$ROOT/examples"
NEGATIVE_DIR="$ROOT/tests/negative"
NATIVE_NEGATIVE_DIR="$ROOT/tests/native-negative"
FLOW_RUNNER="$ROOT/tests/flow-v1/run.sh"
SELFHOST_RUNNER="$ROOT/tests/selfhost/run.sh"
FLOW_START_ID=106

RESULTS_DIR="$ROOT/test-results"
BUILDS_DIR="$RESULTS_DIR/builds"
LOGS_DIR="$RESULTS_DIR/logs"

NEGATIVE_RESULTS_DIR="$ROOT/test-results-negative"
NEGATIVE_BUILDS_DIR="$NEGATIVE_RESULTS_DIR/builds"
NEGATIVE_LOGS_DIR="$NEGATIVE_RESULTS_DIR/logs"

NATIVE_RESULTS_DIR="$ROOT/test-results-native"
NATIVE_BUILDS_DIR="$NATIVE_RESULTS_DIR/builds"
NATIVE_LOGS_DIR="$NATIVE_RESULTS_DIR/logs"

NATIVE_NEGATIVE_RESULTS_DIR="$ROOT/test-results-native-negative"
NATIVE_NEGATIVE_BUILDS_DIR="$NATIVE_NEGATIVE_RESULTS_DIR/builds"
NATIVE_NEGATIVE_LOGS_DIR="$NATIVE_NEGATIVE_RESULTS_DIR/logs"

COMPILER="$ROOT/emerald-stable/emerald-compiler"
CRYSTAL_COMPILER="$ROOT/compiler/bin/emeraldc"
EMERALD_COMPILER="$ROOT/emerald-compiler/emerald-compiler"
PRISM="$ROOT/prism/prism"

CLEAN=true
PLAIN_ERRORS=true
BUILD=true
FULL_DEBUG=false
ONLY_PATTERN=""
START_ID=""

PATCH_STRIP_LEVEL="0"
PATCH_TOOL="patch"
PATCH_DRY_RUN=false
PATCH_REVERSE=false
PATCH_KEEP_GOING=false

COMPILE_TIMEOUT="60s"
RUN_TIMEOUT="20s"

SANDBOX=true
SANDBOX_IMAGE="emerald-selfhost-sandbox"
SANDBOX_DOCKERFILE="$ROOT/docker/Dockerfile.selfhost"
SANDBOX_CONTAINER_NAME="emerald-selfhost-run"
SANDBOX_MEM="8000000000"
SANDBOX_CPUS="$(nproc 2>/dev/null || echo 4)"
SANDBOX_LOG="$ROOT/selfhost-sandbox.log"
SANDBOX_DIAGNOSTICS_ROOT="$ROOT/selfhost-sandbox-diagnostics"
SANDBOX_STATS_INTERVAL="1"
SANDBOX_CGROUP_INTERVAL="2"
SANDBOX_PROCESS_INTERVAL="5"

usage() {
  cat <<'EOF'
Usage:
  ./emerald.sh <command> [options]

Commands:
  patch              Apply all patches from ./patches
  build              Build stage0 and then build the Emerald Compiler
  stage0             Build only the old Crystal based bootstrap compiler
  bootstrap          Build stage0 and then build the Emerald Compiler
  selfhost           Build Stage 1, then Stage 2 and Stage 3 with Emerald itself
  prism              Build the Prism package manager
  positive           Run positive examples from ./examples
  negative           Run expected-fail tests from ./tests/negative
  native             Run native Emerald Compiler smoke tests
  native-negative    Run expected-fail tests through the Emerald Compiler
  hyperalloc-flow    Run the HyperAlloc Flow v1 release-gate suite
  legacy-test        Run old stage0 positive + negative tests
  test               Bootstrap + native + native-negative + Flow v1
  full               Patch + build + positive + negative
  clean              Remove generated result folders
  status             Show project tool status
  help               Show this help

General options:
  --no-clean                 Do not clean old test results
  --fun-errors               Keep random funny diagnostic lines enabled
  --plain-errors             Disable random funny diagnostic lines, default
  --no-build                 For test/full: skip compiler build
  --full-debug               For bootstrap/selfhost: print every compiler phase, loaded file,
                             bound and emitted class plus HyperAlloc Flow runtime statistics
  --only <pattern>           Only run matching examples/tests
  --start <id>               Start numbered examples/tests at this numeric ID
  --compiler <path>          Override stage0 compiler path (default: emerald-stable/emerald-compiler,
                             fallback: emerald-compiler/emerald-compiler, then Crystal emeraldc)
  --emerald-compiler <path>  Override Emerald Compiler path
  --prism <path>             Override Prism path
  --compile-timeout <time>   Compile timeout, default: 60s
  --run-timeout <time>       Run timeout, default: 20s

Selfhost sandbox options (selfhost runs inside a memory-capped Docker
container by default, so a regression OOM-kills the container instead of your PC):
  --no-sandbox               Run selfhost directly on the host, unsandboxed
  --sandbox-mem <size>       Container memory limit, default: 8000000000 (8 GB)
  --sandbox-cpus <n>         Container CPU limit, default: all cores (nproc)
                             Full output is mirrored live to ./selfhost-sandbox.log.
                             Per-run diagnostics are stored below
                             ./selfhost-sandbox-diagnostics/<run-id>/

Patch options:
  --patch-dir <path>         Patch directory, default: ./patches
  --strip <level>            Strip level for patch, default: 0
  --dry-run                  Check patches without applying
  --reverse                  Reverse patches
  --keep-going               Continue after failed patches
  --tool <patch|git>         Patch backend, default: patch

Examples:
  ./emerald.sh full
  ./emerald.sh patch
  ./emerald.sh build
  ./emerald.sh stage0
  ./emerald.sh test
  ./emerald.sh bootstrap
  ./emerald.sh selfhost
  ./emerald.sh native
  ./emerald.sh hyperalloc-flow
  ./emerald.sh test --start 130
  ./emerald.sh positive --only macro
  ./emerald.sh negative --only fiber
  ./emerald.sh test --fun-errors
  ./emerald.sh patch --dry-run
EOF
}

fail() {
  echo "Error: $1"
  exit "${2:-1}"
}

section() {
  echo
  echo "================================================================================"
  echo "$1"
  echo "================================================================================"
  echo
}

run() {
  local title="$1"
  shift

  section "$title"

  "$@"
  local status=$?

  if [[ "$status" -eq 0 ]]; then
    echo
    echo "OK: $title"
    return 0
  fi

  echo
  echo "FAILED: $title"
  echo "Exit:   $status"
  return "$status"
}

configure_errors() {
  if [[ "$PLAIN_ERRORS" == true ]]; then
    export EMERALD_PLAIN_ERRORS=1
    return
  fi

  unset EMERALD_PLAIN_ERRORS
}

duration_ms() {
  local start="$1"
  local end="$2"

  echo $(( (end - start) / 1000000 ))
}

file_id() {
  local file_name
  file_name="$(basename "$1")"

  if [[ "$file_name" =~ ^([0-9]+)_ ]]; then
    echo $((10#${BASH_REMATCH[1]}))
    return 0
  fi

  return 1
}

matches_test_filters() {
  local file="$1"
  local file_name id
  file_name="$(basename "$file")"

  if [[ -n "$ONLY_PATTERN" && "$file_name" != *"$ONLY_PATTERN"* ]]; then
    return 1
  fi

  if [[ -z "$START_ID" ]]; then
    return 0
  fi

  id="$(file_id "$file")" || return 0
  (( id >= START_ID ))
}

configure_native_compiler_env() {
  # The native Emerald compiler needs the LLVM shared library location and
  # the repository root for stdlib resolution. Normal deterministic releases
  # are the default; HYPERALLOC_FLOW_BOOTSTRAP=1 remains an explicit diagnostic
  # compatibility mode for older compiler snapshots.
  export EMERALD_HOME="$ROOT"
  export HYPERALLOC_FLOW_BOOTSTRAP="${HYPERALLOC_FLOW_BOOTSTRAP:-0}"

  if [[ -n "${EMERALD_LLVM_LIB_DIR:-}" && -n "${EMERALD_LLVM_LIBRARY:-}" ]]; then
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

safe_compiler() {
  if [[ ! -x "$COMPILER" && -x "$EMERALD_COMPILER" ]]; then
    COMPILER="$EMERALD_COMPILER"
  fi

  if [[ ! -x "$COMPILER" && -x "$CRYSTAL_COMPILER" ]]; then
    COMPILER="$CRYSTAL_COMPILER"
  fi

  if [[ ! -x "$COMPILER" ]] && command -v emeraldc >/dev/null 2>&1; then
    COMPILER="$(command -v emeraldc)"
  fi

  if [[ ! -x "$COMPILER" ]]; then
    fail "Compiler not executable or not found: $COMPILER. Run ./emerald.sh stage0 to build the Crystal fallback."
  fi

  configure_native_compiler_env
}

cmd_patch() {
  mkdir -p "$PATCH_RESULTS_DIR"
  : > "$PATCH_LOG"

  if [[ "$PATCH_DRY_RUN" != true ]]; then
    mkdir -p "$APPLIED_PATCH_DIR"
  fi

  if [[ ! -d "$PATCH_DIR" ]]; then
    echo "Patch directory not found: $PATCH_DIR" | tee -a "$PATCH_LOG"
    return 1
  fi

  mapfile -t patches < <(find "$PATCH_DIR" -maxdepth 1 -type f \( -name '*.patch' -o -name '*.diff' \) | sort)

  if [[ "${#patches[@]}" -eq 0 ]]; then
    echo "No .patch or .diff files found in: $PATCH_DIR" | tee -a "$PATCH_LOG"
    return 1
  fi

  {
    echo "Patch run"
    echo "========="
    echo "Root:       $ROOT"
    echo "Patch dir:  $PATCH_DIR"
    echo "Tool:       $PATCH_TOOL"
    echo "Strip:      $PATCH_STRIP_LEVEL"
    echo "Dry run:    $PATCH_DRY_RUN"
    echo "Reverse:    $PATCH_REVERSE"
    echo "Keep going: $PATCH_KEEP_GOING"
    echo "Log:        $PATCH_LOG"
    echo
  } | tee -a "$PATCH_LOG"

  local passed=0
  local failed=0

  for patch_file in "${patches[@]}"; do
    local name
    name="$(basename "$patch_file")"

    echo "Applying: $name" | tee -a "$PATCH_LOG"

    apply_one_patch "$patch_file"
    local status=$?

    if [[ "$status" -eq 0 ]]; then
      passed=$((passed + 1))
      echo "OK:       $name" | tee -a "$PATCH_LOG"

      if [[ "$PATCH_DRY_RUN" != true ]]; then
        local applied_target="$APPLIED_PATCH_DIR/$name"
        mv "$patch_file" "$applied_target"
        echo "Moved to: $applied_target" | tee -a "$PATCH_LOG"
      fi

      echo | tee -a "$PATCH_LOG"
      continue
    fi

    failed=$((failed + 1))
    echo "FAILED:   $name" | tee -a "$PATCH_LOG"
    echo "Exit:     $status" | tee -a "$PATCH_LOG"
    echo | tee -a "$PATCH_LOG"

    if [[ "$PATCH_KEEP_GOING" != true ]]; then
      echo "Stopped after first failed patch." | tee -a "$PATCH_LOG"
      echo | tee -a "$PATCH_LOG"
      break
    fi
  done

  {
    echo "Summary"
    echo "======="
    echo "Passed: $passed"
    echo "Failed: $failed"
  } | tee -a "$PATCH_LOG"

  [[ "$failed" -eq 0 ]]
}

apply_one_patch() {
  local patch_file="$1"

  if [[ "$PATCH_TOOL" == "git" ]]; then
    if [[ "$PATCH_DRY_RUN" == true && "$PATCH_REVERSE" == true ]]; then
      git apply --check --reverse "$patch_file" >> "$PATCH_LOG" 2>&1
      return $?
    fi

    if [[ "$PATCH_DRY_RUN" == true ]]; then
      git apply --check "$patch_file" >> "$PATCH_LOG" 2>&1
      return $?
    fi

    if [[ "$PATCH_REVERSE" == true ]]; then
      git apply --reverse "$patch_file" >> "$PATCH_LOG" 2>&1
      return $?
    fi

    git apply "$patch_file" >> "$PATCH_LOG" 2>&1
    return $?
  fi

  if [[ "$PATCH_TOOL" != "patch" ]]; then
    echo "Unknown patch tool: $PATCH_TOOL" >> "$PATCH_LOG"
    return 2
  fi

  local args=("-p$PATCH_STRIP_LEVEL" "--forward" "--reject-file=-")

  if [[ "$PATCH_DRY_RUN" == true ]]; then
    args+=("--dry-run")
  fi

  if [[ "$PATCH_REVERSE" == true ]]; then
    args+=("-R")
  fi

  patch "${args[@]}" < "$patch_file" >> "$PATCH_LOG" 2>&1
}

cmd_stage0() {
  [[ -d "$ROOT/compiler" ]] || fail "Missing compiler directory: $ROOT/compiler"

  run "Build emeraldc" bash -lc "cd '$ROOT/compiler' && shards build emeraldc"
}

cmd_build() {
  cmd_bootstrap
}

positive_header() {
  printf "%-36s %-10s %-10s %-8s %-8s %s\n" "Example" "Compile" "Run" "CExit" "RExit" "Log"
}

cmd_positive() {
  configure_errors
  safe_compiler

  if [[ ! -d "$EXAMPLES_DIR" ]]; then
    echo "Examples directory not found: $EXAMPLES_DIR"
    return 1
  fi

  if [[ "$CLEAN" == true ]]; then
    rm -rf "$RESULTS_DIR"
  fi

  mkdir -p "$LOGS_DIR"
  mkdir -p "$BUILDS_DIR"

  local summary_file="$RESULTS_DIR/summary.txt"
  local failed_file="$RESULTS_DIR/failed.txt"

  : > "$summary_file"
  : > "$failed_file"

  {
    echo "Emerald positive example test run"
    echo "================================="
    echo
    echo "Date:             $(date -Is)"
    echo "Root:             $ROOT"
    echo "Compiler:         $COMPILER"
  echo "Emerald Compiler: $EMERALD_COMPILER"
  echo "Prism:            $PRISM"
    echo "Examples:         $EXAMPLES_DIR"
    echo "Results:          $RESULTS_DIR"
    echo "Compile timeout:  $COMPILE_TIMEOUT"
    echo "Run timeout:      $RUN_TIMEOUT"
    echo "Only pattern:     ${ONLY_PATTERN:-<none>}"
    echo "Start ID:         ${START_ID:-<none>}"
    echo
    positive_header
  } >> "$summary_file"

  positive_header

  local pass_compile=0
  local fail_compile=0
  local pass_run=0
  local fail_run=0
  local skip_run=0

  mapfile -t examples < <(find "$EXAMPLES_DIR" -maxdepth 1 -type f -name '*.ems' | sort -V)

  if [[ "${#examples[@]}" -eq 0 ]]; then
    echo "No .ems examples found in: $EXAMPLES_DIR"
    return 1
  fi

  for example in "${examples[@]}"; do
    local file_name
    file_name="$(basename "$example")"

    if ! matches_test_filters "$example"; then
      continue
    fi

    run_positive_example "$example" "$summary_file" "$failed_file" pass_compile fail_compile pass_run fail_run skip_run
  done

  {
    echo
    echo "Totals"
    echo "======"
    echo "Compile OK:      $pass_compile"
    echo "Compile failed:  $fail_compile"
    echo "Run OK:          $pass_run"
    echo "Run failed:      $fail_run"
    echo "Run skipped:     $skip_run"
    echo
    echo "Failed list:     $failed_file"
    echo "Logs:            $LOGS_DIR"
    echo "Builds:          $BUILDS_DIR"
  } | tee -a "$summary_file"

  [[ "$fail_compile" -eq 0 && "$fail_run" -eq 0 ]]
}

run_positive_example() {
  local example="$1"
  local summary_file="$2"
  local failed_file="$3"
  local -n pass_compile_ref="$4"
  local -n fail_compile_ref="$5"
  local -n pass_run_ref="$6"
  local -n fail_run_ref="$7"
  local -n skip_run_ref="$8"

  local file_name name log_file binary compile_status run_status compile_result run_result
  local start_ns end_ns compile_ms run_ms

  file_name="$(basename "$example")"
  name="${file_name%.ems}"
  log_file="$LOGS_DIR/$name.log"
  binary="$BUILDS_DIR/$name"

  : > "$log_file"

  {
    echo "Example: $name"
    echo "File:    $example"
    echo "Binary:  $binary"
    echo "Log:     $log_file"
    echo "Date:    $(date -Is)"
    echo
    echo "================================================================================"
    echo "Compile command"
    echo "================================================================================"
    echo
    printf '%q ' timeout "$COMPILE_TIMEOUT" "$COMPILER" build "$example" -o "$binary"
    echo
    echo
    echo "================================================================================"
    echo "Compile output"
    echo "================================================================================"
    echo
  } >> "$log_file"

  start_ns="$(date +%s%N)"
  timeout "$COMPILE_TIMEOUT" "$COMPILER" build "$example" -o "$binary" >> "$log_file" 2>&1
  compile_status=$?
  end_ns="$(date +%s%N)"
  compile_ms="$(duration_ms "$start_ns" "$end_ns")"

  if [[ "$compile_status" -eq 0 ]]; then
    compile_result="OK"
    pass_compile_ref=$((pass_compile_ref + 1))
  elif [[ "$compile_status" -eq 124 ]]; then
    compile_result="TIMEOUT"
    fail_compile_ref=$((fail_compile_ref + 1))
  else
    compile_result="FAIL"
    fail_compile_ref=$((fail_compile_ref + 1))
  fi

  {
    echo
    echo "Compile exit code: $compile_status"
    echo "Compile result:    $compile_result"
    echo "Compile duration:  ${compile_ms}ms"
  } >> "$log_file"

  if [[ "$compile_result" != "OK" ]]; then
    run_result="SKIP"
    run_status="-"
    skip_run_ref=$((skip_run_ref + 1))

    printf "%-36s %-10s %-10s %-8s %-8s %s\n" "$name" "$compile_result" "$run_result" "$compile_status" "$run_status" "$log_file" | tee -a "$summary_file"
    echo "$name compile=$compile_result cexit=$compile_status log=$log_file" >> "$failed_file"
    return
  fi

  if [[ ! -x "$binary" ]]; then
    chmod +x "$binary" 2>/dev/null || true
  fi

  {
    echo
    echo "================================================================================"
    echo "Run command"
    echo "================================================================================"
    echo
    printf '%q ' timeout "$RUN_TIMEOUT" "$binary"
    echo
    echo
    echo "================================================================================"
    echo "Run output"
    echo "================================================================================"
    echo
  } >> "$log_file"

  start_ns="$(date +%s%N)"
  timeout "$RUN_TIMEOUT" "$binary" >> "$log_file" 2>&1
  run_status=$?
  end_ns="$(date +%s%N)"
  run_ms="$(duration_ms "$start_ns" "$end_ns")"

  if [[ "$run_status" -eq 0 ]]; then
    run_result="OK"
    pass_run_ref=$((pass_run_ref + 1))
  elif [[ "$run_status" -eq 124 ]]; then
    run_result="TIMEOUT"
    fail_run_ref=$((fail_run_ref + 1))
  else
    run_result="FAIL"
    fail_run_ref=$((fail_run_ref + 1))
  fi

  {
    echo
    echo "Run exit code: $run_status"
    echo "Run result:    $run_result"
    echo "Run duration:  ${run_ms}ms"
  } >> "$log_file"

  if [[ "$run_result" != "OK" ]]; then
    echo "$name run=$run_result rexit=$run_status log=$log_file" >> "$failed_file"
  fi

  printf "%-36s %-10s %-10s %-8s %-8s %s\n" "$name" "$compile_result" "$run_result" "$compile_status" "$run_status" "$log_file" | tee -a "$summary_file"
}

negative_header() {
  printf "%-36s %-18s %-8s %s\n" "Test" "Result" "Exit" "Log"
}

cmd_negative() {
  configure_errors
  safe_compiler

  if [[ ! -d "$NEGATIVE_DIR" ]]; then
    echo "Negative test directory not found: $NEGATIVE_DIR"
    return 1
  fi

  if [[ "$CLEAN" == true ]]; then
    rm -rf "$NEGATIVE_RESULTS_DIR"
  fi

  mkdir -p "$NEGATIVE_LOGS_DIR"
  mkdir -p "$NEGATIVE_BUILDS_DIR"

  local summary_file="$NEGATIVE_RESULTS_DIR/summary.txt"
  local failed_file="$NEGATIVE_RESULTS_DIR/failed.txt"

  : > "$summary_file"
  : > "$failed_file"

  {
    echo "Emerald negative test run"
    echo "========================="
    echo
    echo "Date:             $(date -Is)"
    echo "Root:             $ROOT"
    echo "Compiler:         $COMPILER"
  echo "Emerald Compiler: $EMERALD_COMPILER"
    echo "Tests:            $NEGATIVE_DIR"
    echo "Results:          $NEGATIVE_RESULTS_DIR"
    echo "Compile timeout:  $COMPILE_TIMEOUT"
    echo "Only pattern:     ${ONLY_PATTERN:-<none>}"
    echo "Start ID:         ${START_ID:-<none>}"
    echo
    negative_header
  } >> "$summary_file"

  negative_header

  local expected_fail_ok=0
  local unexpected_ok=0
  local message_mismatch=0
  local timeout_count=0

  mapfile -t tests < <(find "$NEGATIVE_DIR" -maxdepth 1 -type f -name '*.ems' | sort -V)

  if [[ "${#tests[@]}" -eq 0 ]]; then
    echo "No .ems negative tests found in: $NEGATIVE_DIR"
    return 1
  fi

  for test_file in "${tests[@]}"; do
    local file_name
    file_name="$(basename "$test_file")"

    if ! matches_test_filters "$test_file"; then
      continue
    fi

    run_negative_test "$test_file" "$summary_file" "$failed_file" expected_fail_ok unexpected_ok message_mismatch timeout_count
  done

  {
    echo
    echo "Totals"
    echo "======"
    echo "Expected fail OK: $expected_fail_ok"
    echo "Unexpected OK:    $unexpected_ok"
    echo "Message mismatch: $message_mismatch"
    echo "Timeout:          $timeout_count"
    echo
    echo "Failed list:      $failed_file"
    echo "Logs:             $NEGATIVE_LOGS_DIR"
  } | tee -a "$summary_file"

  [[ "$unexpected_ok" -eq 0 && "$message_mismatch" -eq 0 && "$timeout_count" -eq 0 ]]
}

read_expectations() {
  local expect_file="$1"

  if [[ ! -f "$expect_file" ]]; then
    return 0
  fi

  grep -v '^[[:space:]]*$' "$expect_file" | grep -v '^[[:space:]]*#' || true
}

check_expectations() {
  local log_file="$1"
  local expect_file="$2"
  local missing=0

  if [[ ! -f "$expect_file" ]]; then
    return 0
  fi

  while IFS= read -r expected; do
    [[ -z "$expected" ]] && continue

    if grep -Fq "$expected" "$log_file"; then
      continue
    fi

    {
      echo
      echo "Missing expected text:"
      echo "$expected"
    } >> "$log_file"

    missing=$((missing + 1))
  done < <(read_expectations "$expect_file")

  [[ "$missing" -eq 0 ]]
}

run_negative_test() {
  local test_file="$1"
  local summary_file="$2"
  local failed_file="$3"
  local -n expected_fail_ok_ref="$4"
  local -n unexpected_ok_ref="$5"
  local -n message_mismatch_ref="$6"
  local -n timeout_count_ref="$7"

  local file_name name expect_file log_file binary status result

  file_name="$(basename "$test_file")"
  name="${file_name%.ems}"
  expect_file="$NEGATIVE_DIR/$name.expect"
  log_file="$NEGATIVE_LOGS_DIR/$name.log"
  binary="$NEGATIVE_BUILDS_DIR/$name"

  : > "$log_file"

  {
    echo "Test:   $name"
    echo "File:   $test_file"
    echo "Expect: $expect_file"
    echo "Binary: $binary"
    echo "Date:   $(date -Is)"
    echo
    echo "================================================================================"
    echo "Compile command"
    echo "================================================================================"
    echo
    printf '%q ' timeout "$COMPILE_TIMEOUT" "$COMPILER" build "$test_file" -o "$binary"
    echo
    echo
    echo "================================================================================"
    echo "Compile output"
    echo "================================================================================"
    echo
  } >> "$log_file"

  timeout "$COMPILE_TIMEOUT" "$COMPILER" build "$test_file" -o "$binary" >> "$log_file" 2>&1
  status=$?

  {
    echo
    echo "Compile exit code: $status"
  } >> "$log_file"

  if [[ "$status" -eq 0 ]]; then
    result="UNEXPECTED_OK"
    unexpected_ok_ref=$((unexpected_ok_ref + 1))

    echo "$name result=$result log=$log_file" >> "$failed_file"
    printf "%-36s %-18s %-8s %s\n" "$name" "$result" "$status" "$log_file" | tee -a "$summary_file"
    return
  fi

  if [[ "$status" -eq 124 ]]; then
    result="TIMEOUT"
    timeout_count_ref=$((timeout_count_ref + 1))

    echo "$name result=$result log=$log_file" >> "$failed_file"
    printf "%-36s %-18s %-8s %s\n" "$name" "$result" "$status" "$log_file" | tee -a "$summary_file"
    return
  fi

  if check_expectations "$log_file" "$expect_file"; then
    result="EXPECTED_FAIL_OK"
    expected_fail_ok_ref=$((expected_fail_ok_ref + 1))

    printf "%-36s %-18s %-8s %s\n" "$name" "$result" "$status" "$log_file" | tee -a "$summary_file"
    return
  fi

  result="MESSAGE_MISMATCH"
  message_mismatch_ref=$((message_mismatch_ref + 1))

  echo "$name result=$result log=$log_file" >> "$failed_file"
  printf "%-36s %-18s %-8s %s\n" "$name" "$result" "$status" "$log_file" | tee -a "$summary_file"
}


safe_emerald_compiler() {
  if [[ -x "$EMERALD_COMPILER" ]]; then
    return
  fi

  fail "Emerald Compiler not executable or not found: $EMERALD_COMPILER. Run ./emerald.sh bootstrap first."
}

cmd_bootstrap() {
  local status=0

  if [[ "$FULL_DEBUG" == true ]]; then
    export EMERALD_DEBUG=1
    export HYPERALLOC_FLOW_DEBUG=1
  fi

  safe_compiler
  section "Build Emerald Compiler"

  mkdir -p "$ROOT/emerald-compiler"
  "$COMPILER" build "$ROOT/emerald-compiler/src/Main.ems" -o "$EMERALD_COMPILER"
  status=$?

  if [[ "$status" -eq 0 ]]; then
    echo
    echo "Built Emerald Compiler: $EMERALD_COMPILER"
  fi

  return "$status"
}


cmd_selfhost() {
  configure_errors

  if [[ "$FULL_DEBUG" == true ]]; then
    export EMERALD_DEBUG=1
    export HYPERALLOC_FLOW_DEBUG=1
  fi

  if [[ ! -x "$SELFHOST_RUNNER" ]]; then
    fail "Selfhost runner not executable or not found: $SELFHOST_RUNNER"
  fi

  safe_compiler
  local args=()

  if [[ "$BUILD" != true ]]; then
    args+=(--no-build)
  fi

  EMERALD_STAGE0="$COMPILER" EMERALD_STAGE1="$EMERALD_COMPILER" "$SELFHOST_RUNNER" "${args[@]}"
}

sandbox_container_running() {
  local container_name="$1"

  [[ "$(docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null || echo false)" == "true" ]]
}

collect_sandbox_stats() {
  local container_name="$1"
  local output_file="$2"
  local live_file="$3"

  printf 'timestamp,cpu_percent,memory_usage,memory_percent,pids,block_io,network_io\n' > "$output_file"
  : > "$live_file"

  while sandbox_container_running "$container_name"; do
    local timestamp sample cpu memory memory_percent pids block_io network_io
    timestamp="$(date -Is)"
    sample="$(docker stats --no-stream \
      --format '{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.PIDs}}|{{.BlockIO}}|{{.NetIO}}' \
      "$container_name" 2>/dev/null || true)"

    if [[ -n "$sample" ]]; then
      IFS='|' read -r cpu memory memory_percent pids block_io network_io <<< "$sample"

      printf '"%s","%s","%s","%s","%s","%s","%s"\n' \
        "$timestamp" "$cpu" "$memory" "$memory_percent" "$pids" "$block_io" "$network_io" \
        >> "$output_file"

      printf '%s  RAM %s (%s)  CPU %s  PIDs %s  Block %s  Net %s\n' \
        "$timestamp" "$memory" "$memory_percent" "$cpu" "$pids" "$block_io" "$network_io" \
        > "$live_file"
    fi

    sleep "$SANDBOX_STATS_INTERVAL"
  done
}

collect_sandbox_cgroup_memory() {
  local container_name="$1"
  local output_file="$2"

  : > "$output_file"

  while sandbox_container_running "$container_name"; do
    {
      echo "timestamp=$(date -Is)"
      docker exec "$container_name" sh -c '
        for name in memory.current memory.peak memory.swap.current memory.events memory.events.local; do
          file="/sys/fs/cgroup/$name"
          if [ -r "$file" ]; then
            echo "--- $name ---"
            cat "$file"
          fi
        done
      ' 2>/dev/null || true
      echo
    } >> "$output_file"

    sleep "$SANDBOX_CGROUP_INTERVAL"
  done
}

collect_sandbox_processes() {
  local container_name="$1"
  local output_file="$2"

  : > "$output_file"

  while sandbox_container_running "$container_name"; do
    {
      echo "================================================================================"
      echo "timestamp=$(date -Is)"
      docker top "$container_name" -eo pid,ppid,pcpu,pmem,rss,vsz,etimes,args 2>&1 || true
      echo
    } >> "$output_file"

    sleep "$SANDBOX_PROCESS_INTERVAL"
  done
}

write_sandbox_metadata() {
  local diagnostics_dir="$1"
  local run_id="$2"
  local container_name="$3"
  shift 3
  local inner_args=("$@")

  {
    echo "Emerald selfhost sandbox diagnostics"
    echo "===================================="
    echo
    echo "Run ID:          $run_id"
    echo "Started:         $(date -Is)"
    echo "Root:            $ROOT"
    echo "Container:       $container_name"
    echo "Image:           $SANDBOX_IMAGE"
    echo "Memory limit:    $SANDBOX_MEM"
    echo "CPU limit:       $SANDBOX_CPUS"
    echo "Stats interval:  ${SANDBOX_STATS_INTERVAL}s"
    echo "Cgroup interval: ${SANDBOX_CGROUP_INTERVAL}s"
    echo "Process interval:${SANDBOX_PROCESS_INTERVAL}s"
    echo "Inner command:   ./emerald.sh ${inner_args[*]}"
    echo

    echo "Host"
    echo "----"
    uname -a 2>/dev/null || true
    echo
    free -h 2>/dev/null || true
    echo
    ulimit -a 2>/dev/null || true
    echo

    echo "Docker"
    echo "------"
    docker version 2>/dev/null || true
    echo

    echo "Source identity"
    echo "---------------"
    if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo "Git commit: $(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
      echo "Git status:"
      git -C "$ROOT" status --short 2>/dev/null || true
    else
      echo "Git metadata unavailable"
    fi
    echo

    for file in \
      "$ROOT/emerald.sh" \
      "$ROOT/.emerald-flow-revision" \
      "$COMPILER" \
      "$CRYSTAL_COMPILER" \
      "$EMERALD_COMPILER" \
      "$SELFHOST_RUNNER"; do
      if [[ -f "$file" ]]; then
        stat -c '%n | size=%s | modified=%y' "$file" 2>/dev/null || true
        sha256sum "$file" 2>/dev/null || true
      fi
    done

    echo
    echo "Revision markers"
    echo "----------------"
    if [[ -f "$ROOT/.emerald-flow-revision" ]]; then
      cat "$ROOT/.emerald-flow-revision"
    else
      echo ".emerald-flow-revision not present"
    fi

    grep -R -n -m 20 \
      -E 'HYPERALLOC_FLOW_ANALYSIS_REVISION|allocation-canonical-ast-arena-v1|stage2-[A-Za-z0-9._-]+' \
      "$SELFHOST_RUNNER" "$ROOT/emerald-compiler/src" 2>/dev/null || true
  } > "$diagnostics_dir/metadata.txt"

  docker image inspect "$SANDBOX_IMAGE" > "$diagnostics_dir/image-inspect.json" 2>/dev/null || true

  mkdir -p "$diagnostics_dir/source-snapshot"
  for file in "$ROOT/emerald.sh" "$SELFHOST_RUNNER" "$SANDBOX_DOCKERFILE"; do
    if [[ -f "$file" ]]; then
      cp "$file" "$diagnostics_dir/source-snapshot/$(basename "$file")" 2>/dev/null || true
    fi
  done
}

archive_sandbox_diagnostics() {
  local diagnostics_dir="$1"
  local diagnostics_root
  local run_id

  diagnostics_root="$(dirname "$diagnostics_dir")"
  run_id="$(basename "$diagnostics_dir")"

  if command -v zip >/dev/null 2>&1; then
    local archive_path="$diagnostics_root/$run_id.zip"
    (
      cd "$diagnostics_root" || exit 1
      zip -qr "$archive_path" "$run_id"
    ) || return 1
    echo "$archive_path"
    return 0
  fi

  local archive_path="$diagnostics_root/$run_id.tar.gz"
  tar -czf "$archive_path" -C "$diagnostics_root" "$run_id" || return 1
  echo "$archive_path"
}

copy_selfhost_diagnostics() {
  local diagnostics_dir="$1"
  local destination="$diagnostics_dir/selfhost-files"

  mkdir -p "$destination"

  if [[ ! -d "$ROOT/test-results-selfhost" ]]; then
    return
  fi

  (
    cd "$ROOT" || exit 0
    find test-results-selfhost -type f \
      \( -name '*.log' -o -name '*.txt' -o -name '*.json' \) \
      -print0 2>/dev/null \
      | xargs -0 -r cp --parents -t "$destination"
  ) || true
}

write_sandbox_summary() {
  local diagnostics_dir="$1"
  local status="$2"
  local oom_killed="$3"
  local state_error="$4"
  local started_at="$5"
  local finished_at="$6"
  local phase_pattern

  phase_pattern='(=+|\[Selfhost\]|LLVM prelude coverage|Compiler prelude coverage|smoke test|Build Stage [0-9]+|Emit compiler IR|Run .*smoke|Build .*smoke|Emerald Compiler target:|Emerald Compiler triple:|Wrote |Built:|Flow analysis revision:)'

  grep -E "$phase_pattern" "$diagnostics_dir/container.log" 2>/dev/null \
    > "$diagnostics_dir/phase-timeline.txt" || true

  {
    echo "Emerald selfhost sandbox result"
    echo "==============================="
    echo
    echo "Started:      $started_at"
    echo "Finished:     $finished_at"
    echo "Exit code:    $status"
    echo "OOM killed:   $oom_killed"
    echo "Docker error: ${state_error:-<none>}"
    echo "Memory limit: $SANDBOX_MEM"
    echo

    echo "Last resource sample"
    echo "--------------------"
    tail -n 1 "$diagnostics_dir/stats.csv" 2>/dev/null || true
    echo

    echo "Last detected selfhost phases"
    echo "-----------------------------"
    tail -n 100 "$diagnostics_dir/phase-timeline.txt" 2>/dev/null || true
    echo

    echo "Last cgroup memory sample"
    echo "-------------------------"
    tail -n 40 "$diagnostics_dir/cgroup-memory.log" 2>/dev/null || true
    echo

    echo "Last process snapshot"
    echo "---------------------"
    tail -n 60 "$diagnostics_dir/processes.log" 2>/dev/null || true
    echo

    echo "Last container output"
    echo "---------------------"
    tail -n 120 "$diagnostics_dir/container.log" 2>/dev/null || true
  } > "$diagnostics_dir/summary.txt"
}

cmd_selfhost_sandboxed() {
  command -v docker >/dev/null 2>&1 || fail "Docker not found. Install Docker or pass --no-sandbox to run selfhost directly on the host (risk: it can OOM your machine, see docs)."

  local started_at run_id container_name diagnostics_dir
  started_at="$(date -Is)"
  run_id="$(date +%Y%m%d-%H%M%S)-$$"
  container_name="${SANDBOX_CONTAINER_NAME}-${run_id}"
  diagnostics_dir="$SANDBOX_DIAGNOSTICS_ROOT/$run_id"

  mkdir -p "$diagnostics_dir"

  section "Selfhost Sandbox"
  echo "Run ID:       $run_id"
  echo "Container:    $container_name"
  echo "Memory limit: $SANDBOX_MEM   CPUs: $SANDBOX_CPUS"
  echo "Diagnostics:  $diagnostics_dir"
  echo "The selfhost gate runs inside a memory-capped container. If memory usage"
  echo "explodes, Docker kills the container instead of exhausting the host."
  echo

  if ! docker image inspect "$SANDBOX_IMAGE" >/dev/null 2>&1; then
    echo "Building sandbox image (first run only, cached afterwards)..."
    docker build -f "$SANDBOX_DOCKERFILE" -t "$SANDBOX_IMAGE" "$ROOT" || fail "Failed to build sandbox image"
  fi

  local inner_args=(selfhost --no-sandbox)
  [[ "$FULL_DEBUG" == true ]] && inner_args+=(--full-debug)
  [[ "$BUILD" != true ]] && inner_args+=(--no-build)

  : > "$SANDBOX_LOG"
  echo "Live log:     $SANDBOX_LOG"
  echo

  docker run -d --name "$container_name" \
    --init \
    --label "emerald.selfhost.run=$run_id" \
    --memory="$SANDBOX_MEM" --memory-swap="$SANDBOX_MEM" --cpus="$SANDBOX_CPUS" \
    --user "$(id -u):$(id -g)" \
    -v "$ROOT:/workspace" -w /workspace -e EMERALD_SANDBOXED=1 -e HOME=/tmp \
    -e HYPERALLOC_FLOW_BOOTSTRAP="${HYPERALLOC_FLOW_BOOTSTRAP:-0}" \
    "$SANDBOX_IMAGE" ./emerald.sh "${inner_args[@]}" >/dev/null \
    || fail "Failed to start sandbox container"

  write_sandbox_metadata "$diagnostics_dir" "$run_id" "$container_name" "${inner_args[@]}"

  collect_sandbox_stats \
    "$container_name" "$diagnostics_dir/stats.csv" "$diagnostics_dir/stats-live.txt" &
  local stats_pid=$!

  collect_sandbox_cgroup_memory \
    "$container_name" "$diagnostics_dir/cgroup-memory.log" &
  local cgroup_pid=$!

  collect_sandbox_processes \
    "$container_name" "$diagnostics_dir/processes.log" &
  local processes_pid=$!

  docker events \
    --since "$(date -d "$started_at" +%s 2>/dev/null || date +%s)" \
    --filter "container=$container_name" \
    --format '{{json .}}' > "$diagnostics_dir/docker-events.jsonl" 2>&1 &
  local events_pid=$!

  if [[ -t 1 ]] && command -v tmux >/dev/null 2>&1; then
    local session="emerald-selfhost-${run_id//[^A-Za-z0-9_-]/-}"
    tmux kill-session -t "$session" >/dev/null 2>&1 || true
    local log_command stats_command

    printf -v log_command \
      'docker logs -f --timestamps %q 2>&1 | tee -a %q' \
      "$container_name" "$SANDBOX_LOG"

    printf -v stats_command \
      'while [[ "$(docker inspect -f '\''{{.State.Running}}'\'' %q 2>/dev/null || echo false)" == true ]]; do clear; cat %q 2>/dev/null || true; sleep 2; done; cat %q 2>/dev/null || true; sleep 2' \
      "$container_name" "$diagnostics_dir/stats-live.txt" "$diagnostics_dir/stats-live.txt"

    tmux new-session -d -s "$session" "$log_command"
    tmux split-window -v -t "$session" "$stats_command"
    tmux resize-pane -t "$session:0.1" -y 4
    tmux select-pane -t "$session:0.0"
    tmux attach -t "$session"
  else
    echo "(tmux not found -- showing build output only; resource samples are written to $diagnostics_dir/stats.csv)"
    docker logs -f --timestamps "$container_name" 2>&1 | tee -a "$SANDBOX_LOG"
  fi

  local status
  status="$(docker wait "$container_name" 2>/dev/null || true)"

  if [[ ! "$status" =~ ^[0-9]+$ ]]; then
    status=1
  fi

  wait "$stats_pid" 2>/dev/null || true
  wait "$cgroup_pid" 2>/dev/null || true
  wait "$processes_pid" 2>/dev/null || true
  kill "$events_pid" 2>/dev/null || true
  wait "$events_pid" 2>/dev/null || true

  local oom_killed state_error finished_at
  oom_killed="$(docker inspect -f '{{.State.OOMKilled}}' "$container_name" 2>/dev/null || echo false)"
  state_error="$(docker inspect -f '{{.State.Error}}' "$container_name" 2>/dev/null || true)"
  finished_at="$(date -Is)"

  docker inspect "$container_name" > "$diagnostics_dir/container-inspect.json" 2>/dev/null || true
  docker logs --timestamps "$container_name" > "$diagnostics_dir/container.log" 2>&1 || true
  cp "$diagnostics_dir/container.log" "$SANDBOX_LOG" 2>/dev/null || true

  copy_selfhost_diagnostics "$diagnostics_dir"
  write_sandbox_summary \
    "$diagnostics_dir" "$status" "$oom_killed" "$state_error" "$started_at" "$finished_at"

  local diagnostics_archive
  diagnostics_archive="$(archive_sandbox_diagnostics "$diagnostics_dir" 2>/dev/null || true)"

  docker rm -f "$container_name" >/dev/null 2>&1 || true

  echo
  echo "[Selfhost Sandbox] Exit:        $status"
  echo "[Selfhost Sandbox] OOM killed:  $oom_killed"
  echo "[Selfhost Sandbox] Diagnostics: $diagnostics_dir"
  if [[ -n "$diagnostics_archive" ]]; then
    echo "[Selfhost Sandbox] Archive:     $diagnostics_archive"
  fi

  if [[ "$oom_killed" == "true" ]]; then
    echo
    echo "[Selfhost Sandbox] FAIL: Docker confirmed an OOM kill at the $SANDBOX_MEM limit."
    echo "Do not raise the limit yet. Inspect summary.txt, stats.csv, processes.log,"
    echo "cgroup-memory.log and the copied selfhost logs to identify the phase and process."
  elif [[ "$status" == "137" ]]; then
    echo
    echo "[Selfhost Sandbox] FAIL: the container received SIGKILL, but Docker did not mark it as OOM-killed."
    echo "The container inspect data was preserved in the diagnostics directory."
  fi

  return "$status"
}

cmd_prism() {
  local status=0

  safe_compiler
  section "Build Prism"

  mkdir -p "$ROOT/prism"
  "$COMPILER" build "$ROOT/emerald-compiler/src/PrismMain.ems" -o "$PRISM"
  status=$?

  if [[ "$status" -eq 0 ]]; then
    echo
    echo "Built Prism: $PRISM"
  fi

  return "$status"
}

native_header() {
  printf "%-40s %-10s %-10s %-8s %-8s %s\n" "Example" "Compile" "Run" "CExit" "RExit" "Log"
}

cmd_native() {
  configure_errors
  safe_emerald_compiler

  if [[ "$CLEAN" == true ]]; then
    rm -rf "$NATIVE_RESULTS_DIR"
  rm -rf "$NATIVE_NEGATIVE_RESULTS_DIR"
  fi

  mkdir -p "$NATIVE_LOGS_DIR"
  mkdir -p "$NATIVE_BUILDS_DIR"

  local summary_file="$NATIVE_RESULTS_DIR/summary.txt"
  local failed_file="$NATIVE_RESULTS_DIR/failed.txt"

  : > "$summary_file"
  : > "$failed_file"

  {
    echo "Emerald Compiler native smoke test run"
    echo "======================================"
    echo
    echo "Date:             $(date -Is)"
    echo "Root:             $ROOT"
    echo "Emerald Compiler: $EMERALD_COMPILER"
    echo "Examples:         $EXAMPLES_DIR"
    echo "Results:          $NATIVE_RESULTS_DIR"
    echo "Only pattern:     ${ONLY_PATTERN:-<none>}"
    echo "Start ID:         ${START_ID:-<none>}"
    echo
    native_header
  } >> "$summary_file"

  native_header

  local pass_compile=0
  local fail_compile=0
  local pass_run=0
  local fail_run=0
  local skip_run=0

  mapfile -t examples < <(find "$EXAMPLES_DIR" -maxdepth 1 -type f -name '*.ems' | sort -V)

  for example in "${examples[@]}"; do
    local file_name id
    file_name="$(basename "$example")"
    id="$(file_id "$example")" || continue

    if (( id < 58 || id >= FLOW_START_ID )); then
      continue
    fi

    if ! matches_test_filters "$example"; then
      continue
    fi

    run_native_example "$example" "$summary_file" "$failed_file" pass_compile fail_compile pass_run fail_run skip_run
  done

  {
    echo
    echo "Totals"
    echo "======"
    echo "Compile OK:      $pass_compile"
    echo "Compile failed:  $fail_compile"
    echo "Run OK:          $pass_run"
    echo "Run failed:      $fail_run"
    echo "Run skipped:     $skip_run"
    echo
    echo "Failed list:     $failed_file"
    echo "Logs:            $NATIVE_LOGS_DIR"
    echo "Builds:          $NATIVE_BUILDS_DIR"
  } | tee -a "$summary_file"

  [[ "$fail_compile" -eq 0 && "$fail_run" -eq 0 ]]
}

run_native_example() {
  local example="$1"
  local summary_file="$2"
  local failed_file="$3"
  local -n pass_compile_ref="$4"
  local -n fail_compile_ref="$5"
  local -n pass_run_ref="$6"
  local -n fail_run_ref="$7"
  local -n skip_run_ref="$8"

  local file_name name log_file binary compile_status run_status compile_result run_result

  file_name="$(basename "$example")"
  name="${file_name%.ems}"
  log_file="$NATIVE_LOGS_DIR/$name.log"
  binary="$NATIVE_BUILDS_DIR/$name"

  : > "$log_file"

  {
    echo "Example: $name"
    echo "File:    $example"
    echo "Binary:  $binary"
    echo "Log:     $log_file"
    echo "Date:    $(date -Is)"
    echo
    echo "================================================================================"
    echo "Compile command"
    echo "================================================================================"
    echo
    printf '%q ' timeout "$COMPILE_TIMEOUT" "$EMERALD_COMPILER" build "$example" -o "$binary"
    echo
    echo
    echo "================================================================================"
    echo "Compile output"
    echo "================================================================================"
    echo
  } >> "$log_file"

  timeout "$COMPILE_TIMEOUT" "$EMERALD_COMPILER" build "$example" -o "$binary" >> "$log_file" 2>&1
  compile_status=$?

  if [[ "$compile_status" -eq 0 ]]; then
    compile_result="OK"
    pass_compile_ref=$((pass_compile_ref + 1))
  elif [[ "$compile_status" -eq 124 ]]; then
    compile_result="TIMEOUT"
    fail_compile_ref=$((fail_compile_ref + 1))
  else
    compile_result="FAIL"
    fail_compile_ref=$((fail_compile_ref + 1))
  fi

  if [[ "$compile_result" != "OK" ]]; then
    run_result="SKIP"
    run_status="-"
    skip_run_ref=$((skip_run_ref + 1))
    printf "%-40s %-10s %-10s %-8s %-8s %s\n" "$name" "$compile_result" "$run_result" "$compile_status" "$run_status" "$log_file" | tee -a "$summary_file"
    echo "$name compile=$compile_result cexit=$compile_status log=$log_file" >> "$failed_file"
    return
  fi

  chmod +x "$binary" 2>/dev/null || true

  {
    echo
    echo "================================================================================"
    echo "Run command"
    echo "================================================================================"
    echo
    printf '%q ' timeout "$RUN_TIMEOUT" "$binary"
    echo
    echo
    echo "================================================================================"
    echo "Run output"
    echo "================================================================================"
    echo
  } >> "$log_file"

  timeout "$RUN_TIMEOUT" "$binary" >> "$log_file" 2>&1
  run_status=$?

  if [[ "$run_status" -eq 0 ]]; then
    run_result="OK"
    pass_run_ref=$((pass_run_ref + 1))
  elif [[ "$run_status" -eq 124 ]]; then
    run_result="TIMEOUT"
    fail_run_ref=$((fail_run_ref + 1))
  else
    run_result="FAIL"
    fail_run_ref=$((fail_run_ref + 1))
  fi

  if [[ "$run_result" != "OK" ]]; then
    echo "$name run=$run_result rexit=$run_status log=$log_file" >> "$failed_file"
  fi

  printf "%-40s %-10s %-10s %-8s %-8s %s\n" "$name" "$compile_result" "$run_result" "$compile_status" "$run_status" "$log_file" | tee -a "$summary_file"
}


cmd_native_negative() {
  configure_errors
  safe_emerald_compiler

  if [[ ! -d "$NATIVE_NEGATIVE_DIR" ]]; then
    echo "Native negative test directory not found: $NATIVE_NEGATIVE_DIR"
    return 1
  fi

  if [[ "$CLEAN" == true ]]; then
    rm -rf "$NATIVE_NEGATIVE_RESULTS_DIR"
  fi

  mkdir -p "$NATIVE_NEGATIVE_LOGS_DIR"
  mkdir -p "$NATIVE_NEGATIVE_BUILDS_DIR"

  local summary_file="$NATIVE_NEGATIVE_RESULTS_DIR/summary.txt"
  local failed_file="$NATIVE_NEGATIVE_RESULTS_DIR/failed.txt"

  : > "$summary_file"
  : > "$failed_file"

  {
    echo "Emerald Compiler native negative test run"
    echo "========================================="
    echo
    echo "Date:             $(date -Is)"
    echo "Root:             $ROOT"
    echo "Emerald Compiler: $EMERALD_COMPILER"
    echo "Tests:            $NATIVE_NEGATIVE_DIR"
    echo "Results:          $NATIVE_NEGATIVE_RESULTS_DIR"
    echo "Only pattern:     ${ONLY_PATTERN:-<none>}"
    echo "Start ID:         ${START_ID:-<none>}"
    echo
    negative_header
  } >> "$summary_file"

  negative_header

  local expected_fail_ok=0
  local unexpected_ok=0
  local message_mismatch=0
  local timeout_count=0

  mapfile -t tests < <(find "$NATIVE_NEGATIVE_DIR" -maxdepth 1 -type f -name '*.ems' | sort -V)

  for test_file in "${tests[@]}"; do
    local file_name name expect_file log_file binary status result
    file_name="$(basename "$test_file")"
    name="${file_name%.ems}"

    if ! matches_test_filters "$test_file"; then
      continue
    fi

    expect_file="$NATIVE_NEGATIVE_DIR/$name.expect"
    log_file="$NATIVE_NEGATIVE_LOGS_DIR/$name.log"
    binary="$NATIVE_NEGATIVE_BUILDS_DIR/$name"
    : > "$log_file"

    {
      echo "Test:   $name"
      echo "File:   $test_file"
      echo "Expect: $expect_file"
      echo "Binary: $binary"
      echo "Date:   $(date -Is)"
      echo
      printf '%q ' timeout "$COMPILE_TIMEOUT" "$EMERALD_COMPILER" build "$test_file" -o "$binary"
      echo
      echo
    } >> "$log_file"

    timeout "$COMPILE_TIMEOUT" "$EMERALD_COMPILER" build "$test_file" -o "$binary" >> "$log_file" 2>&1
    status=$?

    if [[ "$status" -eq 0 ]]; then
      result="UNEXPECTED_OK"
      unexpected_ok=$((unexpected_ok + 1))
      echo "$name result=$result log=$log_file" >> "$failed_file"
      printf "%-36s %-18s %-8s %s\n" "$name" "$result" "$status" "$log_file" | tee -a "$summary_file"
      continue
    fi

    if [[ "$status" -eq 124 ]]; then
      result="TIMEOUT"
      timeout_count=$((timeout_count + 1))
      echo "$name result=$result log=$log_file" >> "$failed_file"
      printf "%-36s %-18s %-8s %s\n" "$name" "$result" "$status" "$log_file" | tee -a "$summary_file"
      continue
    fi

    if check_expectations "$log_file" "$expect_file"; then
      result="EXPECTED_FAIL_OK"
      expected_fail_ok=$((expected_fail_ok + 1))
      printf "%-36s %-18s %-8s %s\n" "$name" "$result" "$status" "$log_file" | tee -a "$summary_file"
      continue
    fi

    result="MESSAGE_MISMATCH"
    message_mismatch=$((message_mismatch + 1))
    echo "$name result=$result log=$log_file" >> "$failed_file"
    printf "%-36s %-18s %-8s %s\n" "$name" "$result" "$status" "$log_file" | tee -a "$summary_file"
  done

  {
    echo
    echo "Totals"
    echo "======"
    echo "Expected fail OK: $expected_fail_ok"
    echo "Unexpected OK:    $unexpected_ok"
    echo "Message mismatch: $message_mismatch"
    echo "Timeout:          $timeout_count"
  } | tee -a "$summary_file"

  [[ "$unexpected_ok" -eq 0 && "$message_mismatch" -eq 0 && "$timeout_count" -eq 0 ]]
}

cmd_flow() {
  configure_errors
  safe_emerald_compiler

  if [[ ! -x "$FLOW_RUNNER" ]]; then
    fail "Flow v1 runner not executable or not found: $FLOW_RUNNER"
  fi

  local args=()

  if [[ -n "$START_ID" ]]; then
    args+=(--start "$START_ID")
  fi

  if [[ -n "$ONLY_PATTERN" ]]; then
    args+=(--only "$ONLY_PATTERN")
  fi

  EMERALD_COMPILER="$EMERALD_COMPILER" "$FLOW_RUNNER" "${args[@]}"
}

cmd_legacy_test() {
  local status=0

  if [[ "$BUILD" == true ]]; then
    cmd_stage0 || status=$?
  fi

  if [[ "$status" -eq 0 ]]; then
    run "Positive examples" cmd_positive || status=$?
  fi

  if [[ "$status" -eq 0 ]]; then
    run "Negative tests" cmd_negative || status=$?
  fi

  return "$status"
}

cmd_test() {
  local status=0

  if [[ "$BUILD" == true ]]; then
    cmd_bootstrap || status=$?
  fi

  if [[ "$status" -eq 0 ]]; then
    run "Native Emerald Compiler smoke tests" cmd_native || status=$?
  fi

  if [[ "$status" -eq 0 ]]; then
    run "Native Emerald Compiler negative tests" cmd_native_negative || status=$?
  fi

  if [[ "$status" -eq 0 ]]; then
    run "HyperAlloc Flow v1 release gate" cmd_flow || status=$?
  fi

  return "$status"
}

cmd_full() {
  local status=0

  run "Apply patches" cmd_patch || status=$?

  if [[ "$status" -eq 0 && "$BUILD" == true ]]; then
    cmd_bootstrap || status=$?
  fi

  if [[ "$status" -eq 0 ]]; then
    run "Positive examples" cmd_positive || status=$?
  fi

  if [[ "$status" -eq 0 ]]; then
    run "Negative tests" cmd_negative || status=$?
  fi

  if [[ "$status" -eq 0 ]]; then
    run "Native Emerald Compiler smoke tests" cmd_native || status=$?
  fi

  return "$status"
}

cmd_clean() {
  section "Clean"

  rm -rf "$RESULTS_DIR"
  rm -rf "$NEGATIVE_RESULTS_DIR"
  rm -rf "$PATCH_RESULTS_DIR"
  rm -rf "$NATIVE_RESULTS_DIR"
  rm -rf "$NATIVE_NEGATIVE_RESULTS_DIR"
  rm -rf "$ROOT/compiler/bin"

  echo "Removed test-results, test-results-negative, native results, patch-results and compiler/bin"
}

cmd_status() {
  section "Status"

  echo "Root:             $ROOT"
  echo "Compiler:         $COMPILER"
  echo "Emerald Compiler: $EMERALD_COMPILER"
  echo "Prism:            $PRISM"
  echo "Patch dir:        $PATCH_DIR"
  echo "Applied dir:      $APPLIED_PATCH_DIR"
  echo "Examples dir:     $EXAMPLES_DIR"
  echo "Negative dir:     $NEGATIVE_DIR"
  echo "Clean:            $CLEAN"
  echo "Plain errors:     $PLAIN_ERRORS"
  echo "Build:            $BUILD"
  echo "Only pattern:     ${ONLY_PATTERN:-<none>}"
  echo "Start ID:         ${START_ID:-<none>}"
  echo "Compile timeout:  $COMPILE_TIMEOUT"
  echo "Run timeout:      $RUN_TIMEOUT"
  echo "Patch tool:       $PATCH_TOOL"
  echo "Patch strip:      $PATCH_STRIP_LEVEL"
  echo "Sandbox:          $SANDBOX"
  echo "Sandbox image:    $SANDBOX_IMAGE"
  echo "Sandbox memory:   $SANDBOX_MEM"
  echo "Sandbox CPUs:     $SANDBOX_CPUS"
  echo "Sandbox log:      $SANDBOX_LOG"
  echo "Sandbox diag dir: $SANDBOX_DIAGNOSTICS_ROOT"
}

command="${1:-help}"

if [[ $# -gt 0 ]]; then
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-clean)
      CLEAN=false
      shift
      ;;

    --fun-errors)
      PLAIN_ERRORS=false
      shift
      ;;

    --plain-errors)
      PLAIN_ERRORS=true
      shift
      ;;

    --full-debug)
      FULL_DEBUG=true
      shift
      ;;

    --no-build)
      BUILD=false
      shift
      ;;

    --no-sandbox)
      SANDBOX=false
      shift
      ;;

    --sandbox-mem)
      [[ -n "${2:-}" ]] || fail "Missing value for --sandbox-mem"
      SANDBOX_MEM="$2"
      shift 2
      ;;

    --sandbox-cpus)
      [[ -n "${2:-}" ]] || fail "Missing value for --sandbox-cpus"
      SANDBOX_CPUS="$2"
      shift 2
      ;;

    --only)
      [[ -n "${2:-}" ]] || fail "Missing value for --only"
      ONLY_PATTERN="$2"
      shift 2
      ;;

    --start)
      [[ "${2:-}" =~ ^[0-9]+$ ]] || fail "--start requires a numeric example/test ID"
      START_ID=$((10#$2))
      shift 2
      ;;

    --compiler)
      COMPILER="$2"
      shift 2
      ;;

    --emerald-compiler)
      EMERALD_COMPILER="$2"
      shift 2
      ;;

    --prism)
      PRISM="$2"
      shift 2
      ;;

    --compile-timeout)
      COMPILE_TIMEOUT="$2"
      shift 2
      ;;

    --run-timeout)
      RUN_TIMEOUT="$2"
      shift 2
      ;;

    --patch-dir)
      PATCH_DIR="$2"
      shift 2
      ;;

    --strip)
      PATCH_STRIP_LEVEL="$2"
      shift 2
      ;;

    --dry-run)
      PATCH_DRY_RUN=true
      shift
      ;;

    --reverse)
      PATCH_REVERSE=true
      shift
      ;;

    --keep-going)
      PATCH_KEEP_GOING=true
      shift
      ;;

    --tool)
      PATCH_TOOL="$2"
      shift 2
      ;;

    --help|-h)
      usage
      exit 0
      ;;

    *)
      fail "Unknown option: $1"
      ;;
  esac
done

case "$command" in
  patch)
    cmd_patch
    ;;

  build)
    cmd_build
    ;;

  stage0)
    cmd_stage0
    ;;

  bootstrap)
    cmd_bootstrap
    ;;

  selfhost)
    if [[ "$SANDBOX" == true && "${EMERALD_SANDBOXED:-}" != "1" ]]; then
      cmd_selfhost_sandboxed
    else
      cmd_selfhost
    fi
    ;;

  prism)
    cmd_prism
    ;;

  positive)
    cmd_positive
    ;;

  negative)
    cmd_negative
    ;;

  native)
    cmd_native
    ;;

  native-negative)
    cmd_native_negative
    ;;

  hyperalloc-flow|flow)
    cmd_flow
    ;;

  legacy-test)
    cmd_legacy_test
    ;;

  test)
    cmd_test
    ;;

  full)
    cmd_full
    ;;

  clean)
    cmd_clean
    ;;

  status)
    cmd_status
    ;;

  help|--help|-h)
    usage
    ;;

  *)
    usage
    fail "Unknown command: $command"
    ;;
esac
