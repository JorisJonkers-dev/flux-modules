#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  restore-http-api-export --input <file> --namespace <ns> --service <name> --remote-port <port> --path <path> [options]

Options:
  --local-port <port>          Local port-forward port. Default: same as --remote-port.
  --scheme http|https          Local forwarded scheme. Default: http.
  --method <method>            HTTP method. Default: POST.
  --content-type <value>       Request content type. Default: application/json.
  --username-env <name>        Env var containing basic-auth username.
  --password-env <name>        Env var containing basic-auth password.
  --username-file <path>       File containing basic-auth username.
  --password-file <path>       File containing basic-auth password.
  --no-auth                    Send no Authorization header.
  --kubectl <path>             kubectl executable. Default: kubectl.
  --curl <path>                curl executable. Default: curl.
  --dry-run                    Validate inputs and print the restore action.

Imports a caller-owned export file into a Kubernetes service through a local
port-forward. This is suitable for service APIs such as RabbitMQ definitions
imports, but the API path, service, port, and credentials are caller-owned.
EOF
  exit 64
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 69; }
}

require_non_empty() {
  local name="$1" value="$2"
  [[ -n "${value}" ]] || { echo "Missing ${name}" >&2; exit 64; }
}

require_port() {
  local name="$1" value="$2"
  [[ "${value}" =~ ^[0-9]+$ && "${value}" -ge 1 && "${value}" -le 65535 ]] || {
    echo "${name} must be a TCP port: ${value}" >&2
    exit 64
  }
}

read_secret_value() {
  local label="$1" file_path="$2" env_name="$3" value=""
  if [[ -n "${file_path}" ]]; then
    [[ -f "${file_path}" ]] || { echo "${label} file not found: ${file_path}" >&2; exit 66; }
    value="$(tr -d '\r\n' < "${file_path}")"
  elif [[ -n "${env_name}" ]]; then
    value="${!env_name:-}"
  fi
  printf '%s' "${value}"
}

INPUT=""
NAMESPACE=""
SERVICE=""
REMOTE_PORT=""
LOCAL_PORT=""
API_PATH=""
SCHEME="http"
METHOD="POST"
CONTENT_TYPE="application/json"
USERNAME_ENV=""
PASSWORD_ENV=""
USERNAME_FILE=""
PASSWORD_FILE=""
NO_AUTH=false
KUBECTL="kubectl"
CURL="curl"
DRY_RUN=false

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --input) shift; [[ "$#" -gt 0 ]] || usage; INPUT="$1" ;;
    --namespace) shift; [[ "$#" -gt 0 ]] || usage; NAMESPACE="$1" ;;
    --service) shift; [[ "$#" -gt 0 ]] || usage; SERVICE="$1" ;;
    --remote-port) shift; [[ "$#" -gt 0 ]] || usage; REMOTE_PORT="$1" ;;
    --local-port) shift; [[ "$#" -gt 0 ]] || usage; LOCAL_PORT="$1" ;;
    --path) shift; [[ "$#" -gt 0 ]] || usage; API_PATH="$1" ;;
    --scheme) shift; [[ "$#" -gt 0 ]] || usage; SCHEME="$1" ;;
    --method) shift; [[ "$#" -gt 0 ]] || usage; METHOD="$1" ;;
    --content-type) shift; [[ "$#" -gt 0 ]] || usage; CONTENT_TYPE="$1" ;;
    --username-env) shift; [[ "$#" -gt 0 ]] || usage; USERNAME_ENV="$1" ;;
    --password-env) shift; [[ "$#" -gt 0 ]] || usage; PASSWORD_ENV="$1" ;;
    --username-file) shift; [[ "$#" -gt 0 ]] || usage; USERNAME_FILE="$1" ;;
    --password-file) shift; [[ "$#" -gt 0 ]] || usage; PASSWORD_FILE="$1" ;;
    --no-auth) NO_AUTH=true ;;
    --kubectl) shift; [[ "$#" -gt 0 ]] || usage; KUBECTL="$1" ;;
    --curl) shift; [[ "$#" -gt 0 ]] || usage; CURL="$1" ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
  shift
done

require_non_empty "--input" "${INPUT}"
require_non_empty "--namespace" "${NAMESPACE}"
require_non_empty "--service" "${SERVICE}"
require_non_empty "--remote-port" "${REMOTE_PORT}"
require_non_empty "--path" "${API_PATH}"
[[ -f "${INPUT}" ]] || { echo "Input file not found: ${INPUT}" >&2; exit 66; }
require_port "--remote-port" "${REMOTE_PORT}"
if [[ -z "${LOCAL_PORT}" ]]; then
  LOCAL_PORT="${REMOTE_PORT}"
fi
require_port "--local-port" "${LOCAL_PORT}"
case "${SCHEME}" in
  http|https) ;;
  *) echo "--scheme must be http or https: ${SCHEME}" >&2; exit 64 ;;
esac

if [[ "${NO_AUTH}" == "false" ]]; then
  username="$(read_secret_value "Username" "${USERNAME_FILE}" "${USERNAME_ENV}")"
  password="$(read_secret_value "Password" "${PASSWORD_FILE}" "${PASSWORD_ENV}")"
  [[ -n "${username}" && -n "${password}" ]] || {
    echo "Basic auth requires --username-env/--password-env or --username-file/--password-file. Use --no-auth for unauthenticated APIs." >&2
    exit 64
  }
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "Would import $(basename "${INPUT}") to ${NAMESPACE}/svc/${SERVICE}:${REMOTE_PORT}${API_PATH}"
  exit 0
fi

require_command "${KUBECTL}"
require_command "${CURL}"
"${KUBECTL}" get service -n "${NAMESPACE}" "${SERVICE}" >/dev/null

port_forward_log="$(mktemp "${TMPDIR:-/tmp}/flux-modules-port-forward.XXXXXX.log")"
cleanup() {
  if [[ -n "${PORT_FORWARD_PID:-}" ]]; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${PORT_FORWARD_PID}" 2>/dev/null || true
  fi
  rm -f "${port_forward_log}"
}
trap cleanup EXIT

"${KUBECTL}" -n "${NAMESPACE}" port-forward "svc/${SERVICE}" "${LOCAL_PORT}:${REMOTE_PORT}" >"${port_forward_log}" 2>&1 &
PORT_FORWARD_PID=$!

url="${SCHEME}://127.0.0.1:${LOCAL_PORT}${API_PATH}"
for _ in $(seq 1 30); do
  if "${CURL}" -sS --max-time 3 "${url}" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

curl_args=(-fsS -H "content-type: ${CONTENT_TYPE}" -X "${METHOD}" --data-binary "@${INPUT}")
if [[ "${NO_AUTH}" == "false" ]]; then
  curl_args+=(-u "${username}:${password}")
fi

echo "Importing $(basename "${INPUT}") to ${NAMESPACE}/svc/${SERVICE}:${REMOTE_PORT}${API_PATH}"
"${CURL}" "${curl_args[@]}" "${url}" >/dev/null
echo "HTTP API export import finished: ${NAMESPACE}/svc/${SERVICE}:${REMOTE_PORT}${API_PATH}"
