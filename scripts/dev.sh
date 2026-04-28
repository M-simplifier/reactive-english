#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FRONT_PID=""
BACK_PID=""

cleanup() {
  if [[ -n "${FRONT_PID}" ]] && kill -0 "${FRONT_PID}" 2>/dev/null; then
    kill "${FRONT_PID}" 2>/dev/null || true
  fi
  if [[ -n "${BACK_PID}" ]] && kill -0 "${BACK_PID}" 2>/dev/null; then
    kill "${BACK_PID}" 2>/dev/null || true
  fi
}

trap cleanup EXIT INT TERM

cd "${ROOT_DIR}"

./scripts/setup-local-zlib.sh
npm run schema:generate
npm run frontend:watch &
FRONT_PID=$!

./scripts/with-local-zlib.sh cabal run reactive-english-server -- --static-dir frontend/dist &
BACK_PID=$!

wait
