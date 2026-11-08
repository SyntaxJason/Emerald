#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${EMERALD_SANDBOX_IMAGE:-emerald-selfhost-sandbox}"
OUTPUT="$ROOT/test-results-runtime/$(date +%Y%m%d-%H%M%S)-$$"
command -v docker >/dev/null || { echo 'Docker is required for capped runtime tests.' >&2; exit 1; }
docker image inspect "$IMAGE" >/dev/null || { echo "Sandbox image unavailable: $IMAGE" >&2; exit 1; }
mkdir -p "$OUTPUT"

docker run --rm -i --init --network=none --read-only --cap-drop=ALL \
  --security-opt=no-new-privileges --memory=536870912 --memory-swap=536870912 \
  --cpus=2 --pids-limit=128 --ulimit core=0 --user "$(id -u):$(id -g)" \
  --mount "type=bind,src=$ROOT/runtime,dst=/source/runtime,readonly" \
  --mount "type=bind,src=$ROOT/tests/runtime,dst=/source/tests/runtime,readonly" \
  --mount "type=bind,src=$OUTPUT,dst=/output" \
  --tmpfs /tmp:rw,nosuid,size=67108864 \
  -e HYPERALLOC_FLOW_BOOTSTRAP=0 -e HYPERALLOC_FLOW_DEBUG=0 -e HYPERALLOC_FLOW_UAF_HUNT=0 \
  "$IMAGE" timeout --signal=TERM --kill-after=5s 300s bash -s <<'INNER' 2>&1 | tee "$OUTPUT/tests.log"
set -euo pipefail
cd /source
printf 'memory.max='; cat /sys/fs/cgroup/memory.max
printf 'memory.swap.max='; cat /sys/fs/cgroup/memory.swap.max
flags=(-std=c11 -Wall -Wextra -Werror -Iruntime)
clang "${flags[@]}" runtime/src/hyperalloc_flow.c tests/runtime/flow_bond_cycle.c -o /output/flow-tests
/output/flow-tests
sanitizers=(-O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer)
clang "${flags[@]}" "${sanitizers[@]}" runtime/src/hyperalloc_flow.c tests/runtime/flow_bond_cycle.c -o /output/flow-tests-asan
ASAN_OPTIONS=detect_leaks=1 /output/flow-tests-asan
HYPERALLOC_FLOW_DEBUG=1 ASAN_OPTIONS=detect_leaks=1 /output/flow-tests-asan
# Sanitizer builds default to malloc payloads; also check the slot allocator.
HYPERALLOC_FLOW_MALLOC=0 ASAN_OPTIONS=detect_leaks=1 /output/flow-tests-asan
clang "${flags[@]}" -O2 tests/runtime/flow_allocator.c -o /output/flow-allocator
/output/flow-allocator
clang "${flags[@]}" "${sanitizers[@]}" tests/runtime/flow_allocator.c -o /output/flow-allocator-asan
HYPERALLOC_FLOW_MALLOC=0 ASAN_OPTIONS=detect_leaks=1:quarantine_size_mb=32 /output/flow-allocator-asan
ASAN_OPTIONS=detect_leaks=1:quarantine_size_mb=32 /output/flow-allocator-asan
clang "${flags[@]}" "${sanitizers[@]}" tests/runtime/flow_cycle_internals.c -o /output/flow-internals-asan
ASAN_OPTIONS=detect_leaks=1 /output/flow-internals-asan
HYPERALLOC_FLOW_MALLOC=0 ASAN_OPTIONS=detect_leaks=1 /output/flow-internals-asan
clang "${flags[@]}" "${sanitizers[@]}" runtime/src/hyperalloc_flow.c tests/runtime/flow_share_borrowed.c -o /output/flow-share-borrowed-asan
ASAN_OPTIONS=detect_leaks=1 /output/flow-share-borrowed-asan
HYPERALLOC_FLOW_MALLOC=0 ASAN_OPTIONS=detect_leaks=1 /output/flow-share-borrowed-asan
clang "${flags[@]}" "${sanitizers[@]}" runtime/emerald_runtime.c tests/runtime/flow_list_memory.c -ldl -o /output/flow-list-memory-asan
ASAN_OPTIONS=detect_leaks=1 /output/flow-list-memory-asan
HYPERALLOC_FLOW_MALLOC=0 ASAN_OPTIONS=detect_leaks=1 /output/flow-list-memory-asan
clang "${flags[@]}" "${sanitizers[@]}" runtime/emerald_runtime.c tests/runtime/numbers_paths.c -ldl -o /output/numbers-paths-asan
ASAN_OPTIONS=detect_leaks=1 /output/numbers-paths-asan
clang "${flags[@]}" "${sanitizers[@]}" runtime/emerald_runtime.c tests/runtime/runtime_library.c -ldl -lm -o /output/runtime-library-asan
ASAN_OPTIONS=detect_leaks=1 /output/runtime-library-asan
printf 'runtime-sandbox-tests-ok\n' 
INNER
grep -Fxq runtime-sandbox-tests-ok "$OUTPUT/tests.log"
printf 'Runtime tests passed. Results: %s\n' "$OUTPUT"
