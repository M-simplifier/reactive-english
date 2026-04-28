#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="${ROOT_DIR}/.local/zlib/extracted"

if [[ -f "${TARGET_DIR}/usr/include/zlib.h" && -f "${TARGET_DIR}/usr/lib/x86_64-linux-gnu/libz.so" ]]; then
  export C_INCLUDE_PATH="${TARGET_DIR}/usr/include${C_INCLUDE_PATH:+:${C_INCLUDE_PATH}}"
  export LIBRARY_PATH="${TARGET_DIR}/usr/lib/x86_64-linux-gnu${LIBRARY_PATH:+:${LIBRARY_PATH}}"
  export LD_LIBRARY_PATH="${TARGET_DIR}/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi

exec "$@"
