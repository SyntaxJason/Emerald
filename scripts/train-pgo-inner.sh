#!/usr/bin/env bash
set -euo pipefail
# Refuse an uncapped host execution, even if this helper is called directly.
LIMIT="$(cat /sys/fs/cgroup/memory.max)"
SWAP="$(cat /sys/fs/cgroup/memory.swap.max)"
[[ "$LIMIT" != max && "$LIMIT" -le 8589934592 && "$SWAP" == 0 ]] || {
    echo 'PGO requires a cgroup cap of at most 8 GiB and no swap.' >&2; exit 2;
}
SOURCE="$1"; shift
export EMERALD_HOME=/source EMERALD_LLVM_LIB_DIR=/usr/lib EMERALD_LLVM_LIBRARY=LLVM-22
export HYPERALLOC_FLOW_BOOTSTRAP=0 EMERALD_LTO=thin EMERALD_PLAIN_ERRORS=1
COMPILER="${EMERALD_PGO_COMPILER:-/source/emerald-compiler/emerald-compiler}"
mkdir -p /profile/raw
# llvm-profdata merges only this run's profiles; previous results remain intact.
RUN="$(mktemp -d /profile/raw/run-XXXXXXXX)"
env -u EMERALD_PGO_USE EMERALD_PGO_GENERATE="$RUN" \
    "$COMPILER" build "$SOURCE" -o /profile/instrumented
LLVM_PROFILE_FILE="$RUN/%m-%p.profraw" /profile/instrumented "$@" > /profile/training.out
llvm-profdata merge -output=/profile/stdlib.profdata "$RUN"/*.profraw
llvm-profdata show --all-functions --counts /profile/stdlib.profdata > /profile/profile-functions.txt
env -u EMERALD_PGO_GENERATE EMERALD_PGO_USE=/profile/stdlib.profdata \
    "$COMPILER" build "$SOURCE" -o /profile/optimized
/profile/optimized "$@" > /profile/optimized.out
cmp /profile/training.out /profile/optimized.out
sha256sum "$SOURCE" "$COMPILER" /source/runtime/emerald_runtime.c /profile/stdlib.profdata > /profile/manifest.sha256
find /source/runtime /source/stdlib /source/emerald-compiler/src -type f -print0 | sort -z | xargs -0 sha256sum >> /profile/manifest.sha256
clang --version > /profile/toolchain.txt
printf 'PGO training and output comparison passed. Profile: stdlib.profdata\n'
