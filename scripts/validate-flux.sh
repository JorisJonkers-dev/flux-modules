#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  validate-flux --flux-root <path> --cluster-path <path> [options]

Options:
  --apps-path <path>          Directory to search for in-repository Helm charts.
  --enable-helm              Render HelmRelease resources with flux-local and local charts with helm.
  --offline                   Skip network-dependent Flux HelmRelease expansion.
  --retry-attempts <count>    Attempts for flux-local remote chart expansion. Default: 3.
  --retry-delay <seconds>     Delay between flux-local attempts. Default: 10.
  --schema-location <value>   kubeconform schema location. May be repeated.
  --no-strict                Do not pass -strict to kubeconform.
EOF
  exit 64
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 69
  fi
}

require_dir() {
  local name="$1"
  local path="$2"
  if [[ -z "${path}" ]]; then
    echo "Missing required option: ${name}" >&2
    exit 64
  fi
  if [[ ! -d "${path}" ]]; then
    echo "Directory not found for ${name}: ${path}" >&2
    exit 66
  fi
}

retry() {
  local attempts="$1"
  local delay_seconds="$2"
  shift 2

  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    if [[ "${attempt}" -ge "${attempts}" ]]; then
      return 1
    fi
    echo "Command failed; retrying in ${delay_seconds}s (${attempt}/${attempts}): $*" >&2
    sleep "${delay_seconds}"
    attempt=$((attempt + 1))
  done
}

strip_non_resource_documents() {
  local input="$1"
  local output="$2"

  awk '
    function flush() {
      if (!seen) return
      if (haskind || hasapi) {
        if (started) print "---"
        printf "%s", buf
        started = 1
      } else {
        dropped++
        printf "   dropped non-resource document%s (first content line: %s)\n", \
          (src ? " " src : ""), (firstline ? firstline : "<empty>") > "/dev/stderr"
      }
      buf = ""; seen = 0; haskind = 0; hasapi = 0; src = ""; firstline = ""
    }
    /^---[[:space:]]*$/ { flush(); next }
    {
      seen = 1
      buf = buf $0 "\n"
      if (firstline == "" && $0 ~ /[^[:space:]]/ && $0 !~ /^[[:space:]]*#/) { firstline = $0 }
      if ($0 ~ /^kind:[[:space:]]/) { haskind = 1 }
      if ($0 ~ /^apiVersion:[[:space:]]/) { hasapi = 1 }
      line = $0; sub(/^[[:space:]]+/, "", line); if (line ~ /^# Source:/) { src = line }
    }
    END {
      flush()
      if (dropped) printf "==> dropped %d non-resource document(s)\n", dropped > "/dev/stderr"
    }
  ' "${input}" > "${output}"
}

flux_root=""
cluster_path=""
apps_path=""
enable_helm=false
offline=false
strict=true
retry_attempts=3
retry_delay=10
schema_locations=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --flux-root)
      shift
      [[ "$#" -gt 0 ]] || usage
      flux_root="$1"
      ;;
    --cluster-path)
      shift
      [[ "$#" -gt 0 ]] || usage
      cluster_path="$1"
      ;;
    --apps-path)
      shift
      [[ "$#" -gt 0 ]] || usage
      apps_path="$1"
      ;;
    --enable-helm)
      enable_helm=true
      ;;
    --offline)
      offline=true
      ;;
    --retry-attempts)
      shift
      [[ "$#" -gt 0 ]] || usage
      retry_attempts="$1"
      ;;
    --retry-delay)
      shift
      [[ "$#" -gt 0 ]] || usage
      retry_delay="$1"
      ;;
    --schema-location)
      shift
      [[ "$#" -gt 0 ]] || usage
      schema_locations+=("$1")
      ;;
    --no-strict)
      strict=false
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
  shift
done

require_dir "--flux-root" "${flux_root}"
require_dir "--cluster-path" "${cluster_path}"

if [[ -z "${apps_path}" ]]; then
  apps_path="${flux_root}/apps"
fi

if [[ "${#schema_locations[@]}" -eq 0 ]]; then
  schema_locations=(
    "default"
    "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
    "https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/{{.ResourceKind}}-{{.ResourceAPIVersion}}.json"
  )
fi

require_command kustomize
require_command kubeconform
if [[ "${enable_helm}" == "true" ]]; then
  require_command find
  require_command helm
  if [[ "${offline}" != "true" ]]; then
    require_command flux-local
  fi
fi

render_output="$(mktemp "${TMPDIR:-/tmp}/flux-modules-flux.XXXXXX.yaml")"
trap 'rm -f "${render_output}"' EXIT

echo "==> kustomize build ${cluster_path}"
kustomize build "${cluster_path}" > "${render_output}"

if [[ "${enable_helm}" == "true" ]]; then
  if [[ "${offline}" == "true" ]]; then
    echo "==> skipping flux-local remote chart expansion (--offline)"
  else
    echo "==> flux-local build all --enable-helm ${flux_root}"
    retry "${retry_attempts}" "${retry_delay}" flux-local build all --enable-helm "${flux_root}" >> "${render_output}"
  fi

  if [[ -d "${apps_path}" ]]; then
    while IFS= read -r chart_file; do
      chart_dir="$(dirname "${chart_file}")"
      release_name="$(basename "${chart_dir}")"
      echo "==> helm template ${release_name} ${chart_dir}"
      helm template "${release_name}" "${chart_dir}" >> "${render_output}"
    done < <(find "${apps_path}" -name Chart.yaml | sort)
  fi
fi

echo "==> drop non-resource documents before kubeconform"
stripped_output="$(mktemp "${TMPDIR:-/tmp}/flux-modules-flux-stripped.XXXXXX.yaml")"
strip_non_resource_documents "${render_output}" "${stripped_output}"
rm -f "${render_output}"
render_output="${stripped_output}"

kubeconform_args=(-summary)
if [[ "${strict}" == "true" ]]; then
  kubeconform_args+=(-strict)
fi
for schema_location in "${schema_locations[@]}"; do
  kubeconform_args+=(-schema-location "${schema_location}")
done

echo "==> kubeconform ${render_output}"
kubeconform "${kubeconform_args[@]}" "${render_output}"
