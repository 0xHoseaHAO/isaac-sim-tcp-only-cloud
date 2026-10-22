# Shared helpers for isaac-sim-tcp-only-cloud scripts.
# shellcheck shell=bash

_ISAAC_TCP_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISAAC_TCP_ROOT="${ISAAC_TCP_ROOT:-$(cd "${_ISAAC_TCP_SCRIPTS_DIR}/.." && pwd)}"

load_env_file() {
  local env_file="${1:-${ISAAC_TCP_ROOT}/config/.env}"
  if [[ -f "${env_file}" ]]; then
    # shellcheck disable=SC1090
    set -a
    source "${env_file}"
    set +a
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

detect_host_ip() {
  if [[ -n "${HOST_IP:-}" ]]; then
    echo "${HOST_IP}"
    return
  fi
  local ip
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  echo "${ip:-127.0.0.1}"
}

ensure_runtime_dir() {
  mkdir -p "${XDG_RUNTIME_DIR:-/tmp/runtime-root}"
  chmod 700 "${XDG_RUNTIME_DIR:-/tmp/runtime-root}"
}
