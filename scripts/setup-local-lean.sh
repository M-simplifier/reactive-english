#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOLING_DIR="${ROOT_DIR}/.tooling"
ELAN_HOME="${TOOLING_DIR}/elan"
HOME_DIR="${TOOLING_DIR}/home"
ELAN_BIN="${ELAN_HOME}/bin/elan"

if [[ -x "${ELAN_BIN}" ]]; then
  exit 0
fi

mkdir -p "${TOOLING_DIR}" "${HOME_DIR}"

export ELAN_HOME
export HOME="${HOME_DIR}"

curl -fsSL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none
