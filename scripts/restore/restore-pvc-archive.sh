#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  restore-pvc-archive --namespace <ns> (--pvc <name> | --pvc-match <substring>) --archive <file.tar.gz> [options]

Options:
  --strip-components <n>   Tar strip count before writing into PVC root. Default: 0.
  --pod-name <name>        Temporary restore pod name. Default: restore-<pvc>.
  --image <image>          Restore pod image. Required consumer input for non-dry-run.
  --kubectl <path>         kubectl executable. Default: kubectl.
  --wipe-target            Delete existing PVC contents before extraction.
  --keep-pod               Leave the restore pod behind after completion.
  --dry-run                Validate inputs and print the restore action.
  --print-manifest         Render the temporary restore pod manifest and exit.

Restores a local tar.gz archive into a caller-supplied PVC by streaming it into
a temporary pod. No namespace, PVC, image, or workload name is embedded.
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

require_non_negative_int() {
  local name="$1" value="$2"
  [[ "${value}" =~ ^[0-9]+$ ]] || { echo "${name} must be a non-negative integer: ${value}" >&2; exit 64; }
}

pod_safe_name() {
  printf '%s' "$1" | tr -c '[:alnum:]-' '-'
}

render_manifest() {
  cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/managed-by: flux-modules-restore-toolkit
spec:
  restartPolicy: Never
  containers:
    - name: restore
      image: ${IMAGE}
      command:
        - /bin/sh
        - -ec
        - |
          trap : TERM INT
          sleep infinity & wait
      volumeMounts:
        - name: data
          mountPath: /restore
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: ${PVC_NAME}
EOF
}

NAMESPACE=""
PVC_NAME=""
PVC_MATCH=""
ARCHIVE=""
STRIP_COMPONENTS=0
POD_NAME=""
IMAGE=""
KUBECTL="kubectl"
WIPE_TARGET=false
KEEP_POD=false
DRY_RUN=false
PRINT_MANIFEST=false

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --namespace) shift; [[ "$#" -gt 0 ]] || usage; NAMESPACE="$1" ;;
    --pvc) shift; [[ "$#" -gt 0 ]] || usage; PVC_NAME="$1" ;;
    --pvc-match) shift; [[ "$#" -gt 0 ]] || usage; PVC_MATCH="$1" ;;
    --archive) shift; [[ "$#" -gt 0 ]] || usage; ARCHIVE="$1" ;;
    --strip-components) shift; [[ "$#" -gt 0 ]] || usage; STRIP_COMPONENTS="$1" ;;
    --pod-name) shift; [[ "$#" -gt 0 ]] || usage; POD_NAME="$1" ;;
    --image) shift; [[ "$#" -gt 0 ]] || usage; IMAGE="$1" ;;
    --kubectl) shift; [[ "$#" -gt 0 ]] || usage; KUBECTL="$1" ;;
    --wipe-target) WIPE_TARGET=true ;;
    --keep-pod) KEEP_POD=true ;;
    --dry-run) DRY_RUN=true ;;
    --print-manifest) PRINT_MANIFEST=true ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
  shift
done

require_non_empty "--namespace" "${NAMESPACE}"
require_non_empty "--archive" "${ARCHIVE}"
require_non_empty "--image" "${IMAGE}"
require_non_negative_int "--strip-components" "${STRIP_COMPONENTS}"
[[ -f "${ARCHIVE}" ]] || { echo "Archive not found: ${ARCHIVE}" >&2; exit 66; }

if [[ -n "${PVC_NAME}" && -n "${PVC_MATCH}" ]]; then
  echo "Use either --pvc or --pvc-match, not both." >&2
  exit 64
fi
if [[ -z "${PVC_NAME}" && -z "${PVC_MATCH}" ]]; then
  echo "One of --pvc or --pvc-match is required." >&2
  exit 64
fi
if [[ -z "${PVC_NAME}" && ( "${DRY_RUN}" == "true" || "${PRINT_MANIFEST}" == "true" ) ]]; then
  echo "--pvc-match requires kubectl lookup; use --pvc for --dry-run or --print-manifest." >&2
  exit 64
fi

if [[ -n "${PVC_MATCH}" ]]; then
  require_command "${KUBECTL}"
  if command -v jq >/dev/null 2>&1; then
    mapfile -t pvc_matches < <("${KUBECTL}" get pvc -n "${NAMESPACE}" -o json | jq -r '.items[].metadata.name' | awk -v needle="${PVC_MATCH}" 'index($0, needle) > 0')
  else
    mapfile -t pvc_matches < <("${KUBECTL}" get pvc -n "${NAMESPACE}" --no-headers -o custom-columns=NAME:.metadata.name | awk -v needle="${PVC_MATCH}" 'index($0, needle) > 0')
  fi
  if [[ "${#pvc_matches[@]}" -eq 0 ]]; then
    echo "No PVC in namespace ${NAMESPACE} matched substring: ${PVC_MATCH}" >&2
    exit 1
  fi
  if [[ "${#pvc_matches[@]}" -gt 1 ]]; then
    printf 'PVC match %s was ambiguous in %s:\n' "${PVC_MATCH}" "${NAMESPACE}" >&2
    printf '  %s\n' "${pvc_matches[@]}" >&2
    exit 1
  fi
  PVC_NAME="${pvc_matches[0]}"
fi

if [[ -z "${POD_NAME}" ]]; then
  POD_NAME="restore-$(pod_safe_name "${PVC_NAME}")"
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "Would restore $(basename "${ARCHIVE}") into PVC ${NAMESPACE}/${PVC_NAME} using pod ${POD_NAME}"
  exit 0
fi

if [[ "${PRINT_MANIFEST}" == "true" ]]; then
  render_manifest
  exit 0
fi

require_command "${KUBECTL}"
"${KUBECTL}" get pvc -n "${NAMESPACE}" "${PVC_NAME}" >/dev/null

cleanup() {
  if [[ "${KEEP_POD}" == "false" ]]; then
    "${KUBECTL}" delete pod -n "${NAMESPACE}" "${POD_NAME}" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "Preparing restore pod ${POD_NAME} for PVC ${PVC_NAME} in namespace ${NAMESPACE}"
"${KUBECTL}" delete pod -n "${NAMESPACE}" "${POD_NAME}" --ignore-not-found --wait=true >/dev/null 2>&1 || true
render_manifest | "${KUBECTL}" apply -f -
"${KUBECTL}" wait -n "${NAMESPACE}" --for=condition=Ready "pod/${POD_NAME}" --timeout=180s >/dev/null

if [[ "${WIPE_TARGET}" == "true" ]]; then
  echo "Wiping existing contents from PVC ${PVC_NAME}"
  "${KUBECTL}" exec -n "${NAMESPACE}" "${POD_NAME}" -- sh -ec 'find /restore -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +'
fi

echo "Restoring $(basename "${ARCHIVE}") into PVC ${PVC_NAME}"
"${KUBECTL}" exec -i -n "${NAMESPACE}" "${POD_NAME}" -- tar -xzpf - -C /restore --strip-components "${STRIP_COMPONENTS}" < "${ARCHIVE}"
echo "PVC restore finished: ${NAMESPACE}/${PVC_NAME}"
