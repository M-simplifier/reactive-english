#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PORT=8080
ENV_FILE="${ROOT_DIR}/.env.local"

cd "${ROOT_DIR}"

load_local_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
  fi
}

write_local_env_var() {
  local key="$1"
  local value="$2"
  local temp_file

  touch "${ENV_FILE}"
  chmod 600 "${ENV_FILE}" 2>/dev/null || true
  temp_file="$(mktemp "${ENV_FILE}.XXXXXX")"
  grep -v "^${key}=" "${ENV_FILE}" >"${temp_file}" || true
  printf '%s=%q\n' "${key}" "${value}" >>"${temp_file}"
  mv "${temp_file}" "${ENV_FILE}"
  chmod 600 "${ENV_FILE}" 2>/dev/null || true
}

auth_dev_mode_is_enabled() {
  case "${AUTH_DEV_MODE:-}" in
    1 | true | TRUE | yes | on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_auth_env() {
  export AUTH_DEV_MODE="${AUTH_DEV_MODE:-1}"

  if [[ -n "${GOOGLE_CLIENT_ID:-}" ]]; then
    return
  fi

  if [[ ! -t 0 ]]; then
    if auth_dev_mode_is_enabled; then
      printf 'GOOGLE_CLIENT_ID is not set; starting with dev login only.\n'
    else
      printf 'GOOGLE_CLIENT_ID is not set and AUTH_DEV_MODE is disabled; no login provider will be available.\n'
    fi
    return
  fi

  printf '\nGoogle Client ID is not configured.\n'
  if auth_dev_mode_is_enabled; then
    printf 'Paste your Web client ID, or press Enter to start with dev login only:\n> '
  else
    printf 'Paste your Web client ID, or press Enter to continue without a login provider:\n> '
  fi
  read -r google_client_id_input

  if [[ -z "${google_client_id_input}" ]]; then
    if auth_dev_mode_is_enabled; then
      printf 'Starting with dev login only. You can add GOOGLE_CLIENT_ID later in .env.local.\n'
    else
      printf 'Starting without Google Sign-In. AUTH_DEV_MODE is disabled, so no local login lane will be available.\n'
    fi
    return
  fi

  export GOOGLE_CLIENT_ID="${google_client_id_input}"

  printf 'Save this client ID to .env.local for future npm start runs? [Y/n]: '
  read -r save_answer
  case "${save_answer}" in
    n | N | no | NO | No)
      printf 'Using the client ID for this run only.\n'
      ;;
    *)
      write_local_env_var "GOOGLE_CLIENT_ID" "${GOOGLE_CLIENT_ID}"
      printf 'Saved GOOGLE_CLIENT_ID to .env.local.\n'
      ;;
  esac
}

load_local_env
ensure_auth_env

if [[ ! -d node_modules ]]; then
  npm install
fi

if [[ ! -d frontend/node_modules ]]; then
  npm --prefix frontend install
fi

ARGS=("$@")
for ((i = 0; i < ${#ARGS[@]}; i++)); do
  case "${ARGS[$i]}" in
    --port)
      if ((i + 1 < ${#ARGS[@]})); then
        PORT="${ARGS[$((i + 1))]}"
      fi
      ;;
    --port=*)
      PORT="${ARGS[$i]#--port=}"
      ;;
  esac
done

./scripts/setup-local-zlib.sh
npm run schema:generate
npm --prefix frontend run build

printf '\nReactive English will start on:\n'
printf '  http://localhost:%s\n\n' "${PORT}"
if [[ -n "${GOOGLE_CLIENT_ID:-}" && "${PORT}" != "8080" ]]; then
  printf 'Google Sign-In is configured. Make sure this origin is also authorized in Google Console:\n'
  printf '  http://localhost:%s\n\n' "${PORT}"
fi

./scripts/with-local-zlib.sh cabal run reactive-english-server -- --static-dir frontend/dist "$@"
