#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${LEARNING_PORT:-8090}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to serve the visual learning resource." >&2
  exit 1
fi

echo "Reactive English visual learning resource"
echo "URL: http://localhost:${PORT}"
echo "Directory: ${ROOT_DIR}/learning/visual"
echo

cd "${ROOT_DIR}"
python3 -m http.server "${PORT}" --directory learning/visual
