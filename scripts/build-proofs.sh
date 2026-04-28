#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "${ROOT_DIR}/proof"
"${ROOT_DIR}/scripts/with-local-lean.sh" lake build
