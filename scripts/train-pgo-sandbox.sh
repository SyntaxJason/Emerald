#!/usr/bin/env bash
# Train and apply an LLVM profile inside a capped, network-isolated container.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -lt 2 ]]; then
    echo 'Usage: scripts/train-pgo-sandbox.sh SOURCE.ems OUTPUT_DIRECTORY [program arguments...]' >&2
    exit 2
fi
SOURCE="$(realpath "$1")"
OUTPUT="$(realpath -m "$2")"
shift 2
case "$SOURCE" in "$ROOT"/*) SOURCE_REL="${SOURCE#"$ROOT"/}" ;; *) echo 'Training source must be inside the Emerald checkout.' >&2; exit 2 ;; esac
mkdir -p "$OUTPUT"
IMAGE="${EMERALD_SANDBOX_IMAGE:-emerald-selfhost-sandbox}"
docker run --rm --init --network=none --read-only --cap-drop=ALL \
    --security-opt=no-new-privileges --memory=6000000000 --memory-swap=6000000000 \
    --cpus=2 --pids-limit=128 --ulimit core=0 --user "$(id -u):$(id -g)" \
    --mount "type=bind,src=$ROOT,dst=/source,readonly" \
    --mount "type=bind,src=$OUTPUT,dst=/profile" \
    --tmpfs /tmp:rw,exec,nosuid,size=1073741824 \
    "$IMAGE" timeout --signal=TERM --kill-after=5s 1200s \
    bash /source/scripts/train-pgo-inner.sh "/source/$SOURCE_REL" "$@"
