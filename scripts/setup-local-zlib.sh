#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="${ROOT_DIR}/.local/zlib"

if [[ -f "${TARGET_DIR}/extracted/usr/include/zlib.h" && -f "${TARGET_DIR}/extracted/usr/lib/x86_64-linux-gnu/libz.so" ]]; then
  exit 0
fi

mkdir -p "${TARGET_DIR}"
cd "${TARGET_DIR}"

if [[ ! -f zlib1g-dev_*.deb ]]; then
  apt-get download zlib1g-dev >/dev/null
fi

dpkg-deb -x zlib1g-dev_*.deb extracted
