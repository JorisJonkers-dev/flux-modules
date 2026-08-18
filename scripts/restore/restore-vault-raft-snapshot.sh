#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  restore-vault-raft-snapshot --snapshot <vault-raft.snapshot> --namespace <ns> --pod <name> [options]

Options:
  --container <name>          Vault container name. Default: vault.
  --vault-addr <url>          Address used inside the pod. Default: http://127.0.0.1:8200.
  --vault-token-env <name>    Environment variable containing the token. Default: VAULT_TOKEN.
  --vault-token-file <path>   File containing the token. Overrides --vault-token-env.
  --kubectl <path>            kubectl executable. Default: kubectl.
  --dry-run                   Validate inputs and print the restore action.

Restores a local Vault raft snapshot into a caller-supplied Vault pod. No
namespace, pod name, token, or Vault path is embedded in this script.
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

read_token() {
  local token=""
  if [[ -n "${VAULT_TOKEN_FILE}" ]]; then
    [[ -f "${VAULT_TOKEN_FILE}" ]] || { echo "Vault token file not found: ${VAULT_TOKEN_FILE}" >&2; exit 66; }
    token="$(tr -d '\r\n' < "${VAULT_TOKEN_FILE}")"
  else
    token="${!VAULT_TOKEN_ENV:-}"
  fi
  [[ -n "${token}" ]] || { echo "Vault token is required. Set ${VAULT_TOKEN_ENV} or pass --vault-token-file." >&2; exit 64; }
  printf '%s' "${token}"
}

SNAPSHOT=""
NAMESPACE=""
POD_NAME=""
CONTAINER_NAME="vault"
VAULT_ADDR="http://127.0.0.1:8200"
VAULT_TOKEN_ENV="VAULT_TOKEN"
VAULT_TOKEN_FILE=""
KUBECTL="kubectl"
DRY_RUN=false

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --snapshot) shift; [[ "$#" -gt 0 ]] || usage; SNAPSHOT="$1" ;;
    --namespace) shift; [[ "$#" -gt 0 ]] || usage; NAMESPACE="$1" ;;
    --pod) shift; [[ "$#" -gt 0 ]] || usage; POD_NAME="$1" ;;
    --container) shift; [[ "$#" -gt 0 ]] || usage; CONTAINER_NAME="$1" ;;
    --vault-addr) shift; [[ "$#" -gt 0 ]] || usage; VAULT_ADDR="$1" ;;
    --vault-token-env) shift; [[ "$#" -gt 0 ]] || usage; VAULT_TOKEN_ENV="$1" ;;
    --vault-token-file) shift; [[ "$#" -gt 0 ]] || usage; VAULT_TOKEN_FILE="$1" ;;
    --kubectl) shift; [[ "$#" -gt 0 ]] || usage; KUBECTL="$1" ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
  shift
done

require_non_empty "--snapshot" "${SNAPSHOT}"
require_non_empty "--namespace" "${NAMESPACE}"
require_non_empty "--pod" "${POD_NAME}"
require_non_empty "--container" "${CONTAINER_NAME}"
require_non_empty "--vault-addr" "${VAULT_ADDR}"
[[ -f "${SNAPSHOT}" ]] || { echo "Snapshot not found: ${SNAPSHOT}" >&2; exit 66; }

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "Would restore $(basename "${SNAPSHOT}") into Vault pod ${NAMESPACE}/${POD_NAME} container ${CONTAINER_NAME}"
  exit 0
fi

require_command "${KUBECTL}"
VAULT_TOKEN_VALUE="$(read_token)"

"${KUBECTL}" get pod -n "${NAMESPACE}" "${POD_NAME}" >/dev/null
"${KUBECTL}" wait -n "${NAMESPACE}" --for=condition=Ready "pod/${POD_NAME}" --timeout=180s >/dev/null

echo "Restoring Vault raft snapshot from ${SNAPSHOT}"
"${KUBECTL}" exec -i -n "${NAMESPACE}" -c "${CONTAINER_NAME}" "${POD_NAME}" -- \
  env "VAULT_ADDR=${VAULT_ADDR}" "VAULT_TOKEN=${VAULT_TOKEN_VALUE}" \
  sh -ec 'cat >/tmp/flux-modules-vault-raft.snapshot && vault operator raft snapshot restore -force /tmp/flux-modules-vault-raft.snapshot && rm -f /tmp/flux-modules-vault-raft.snapshot' \
  < "${SNAPSHOT}"

echo "Vault raft snapshot restore finished: ${NAMESPACE}/${POD_NAME}"
