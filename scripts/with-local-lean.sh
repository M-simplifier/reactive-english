#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOLING_DIR="${ROOT_DIR}/.tooling"
ELAN_HOME="${TOOLING_DIR}/elan"
HOME_DIR="${TOOLING_DIR}/home"

"${ROOT_DIR}/scripts/setup-local-lean.sh"

export ELAN_HOME
export HOME="${HOME_DIR}"
export PATH="${ELAN_HOME}/bin:${PATH}"

exec "$@"
