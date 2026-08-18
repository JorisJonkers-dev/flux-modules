#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

failures=()

record_failure() {
  failures+=("$1")
}

require_path() {
  local path="$1"
  [[ -e "${path}" ]] || record_failure "Missing required path: ${path}"
}

forbid_path() {
  local path="$1"
  [[ ! -e "${path}" ]] || record_failure "Forbidden moved path present: ${path}"
}

check_required_paths() {
  local required=(
    README.md
    LICENSE
    .editorconfig
    .gitattributes
    .gitignore
    .github/CODEOWNERS
    docs/dns-zone-policy.md
    docs/restore-toolkit.md
    docs/runbooks/flux-bootstrap-playbook.md
    docs/runbooks/stateful-restore-playbook.md
    docs/strict-flux-render-validation.md
    examples/backup/manifest.tsv
    examples/backup/expected-paths.tsv
    examples/backup/snapshot-plugins.tsv
    examples/restore/snapshot-restore-plugins.tsv
    packs/flux-core/README.md
    packs/edge/README.md
    packs/edge-middleware/README.md
    packs/edge-middleware/profiles.yaml
    packs/edge-middleware/default-public.yaml
    packs/edge-middleware/sso-forward-auth.yaml
    packs/longhorn-site-storage/README.md
    packs/gateway-api-preview/README.md
    packs/rabbitmq-data-service/README.md
    packs/observability/README.md
    schemas/crds
    scripts/validate-flux.sh
    scripts/validate-flux-render.sh
    scripts/validate-platform-render.sh
    scripts/backup/backup-service-state.sh
    scripts/backup/backup-service-snapshots.sh
    scripts/backup/verify-backup-run.sh
    scripts/backup/audit-backup-scope.sh
    scripts/restore/restore-hostpath-archive.sh
    scripts/restore/restore-http-api-export.sh
    scripts/restore/restore-pvc-archive.sh
    scripts/restore/restore-service-snapshots.sh
    scripts/restore/restore-vault-raft-snapshot.sh
    scripts/restore/verify-restore-run.sh
    scripts/vault/compile-vault-bootstrap-policy.py
    fixtures/vault-bootstrap-policy/minimal-policy.yaml
    fixtures/vault-bootstrap-policy/full-policy.yaml
    tests/scripts/backup-tooling-smoke.sh
    tests/scripts/restore-tooling-smoke.sh
    tests/scripts/flux-render-validation-smoke.sh
    .github/workflows/ci.yml
    .github/workflows/add-to-project.yml
    .github/workflows/repository-hygiene.yml
    .github/workflows/release.yml
    renovate.json
    release-please-config.json
    .release-please-manifest.json
  )

  local path
  for path in "${required[@]}"; do
    require_path "${path}"
  done
}

check_forbidden_paths() {
  local forbidden=(
    "flake"".nix"
    flake.lock
    lib
    modules
    fixtures/nixos-host-roles
    skeletons/nixos-host-roles
    tests/module-fixture.nix
    scripts/bootstrap-k3s-agent-token.sh
    scripts/vault/__pycache__
    platform/inventory/fleet.yaml
    platform/cluster/flux/apps
    platform/cluster/flux/clusters
    platform/cluster/flux/rendered
    nomad
    consul
  )

  local path
  for path in "${forbidden[@]}"; do
    forbid_path "${path}"
  done
}

check_shell_syntax() {
  local path
  while IFS= read -r path; do
    bash -n "${path}" || record_failure "Invalid shell syntax: ${path}"
  done < <(find scripts tests -type f -name '*.sh' | sort)
}

check_python_syntax() {
  local path
  while IFS= read -r path; do
    python3 - "${path}" <<'PY' || record_failure "Invalid Python syntax: ${path}"
import ast
import sys
from pathlib import Path

path = Path(sys.argv[1])
ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
PY
  done < <(find scripts -type f -name '*.py' | sort)
}

check_json_yaml() {
  python3 - <<'PY'
import json
import shutil
import subprocess
import sys
from pathlib import Path

root = Path(".")
failures = []

for path in root.rglob("*"):
    if ".git" in path.parts or not path.is_file():
        continue
    if path.suffix.lower() == ".json":
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            failures.append(f"{path}: invalid JSON: {exc}")

yaml_paths = [
    path for path in root.rglob("*")
    if ".git" not in path.parts and path.is_file() and path.suffix.lower() in {".yaml", ".yml"}
]
if yaml_paths:
    try:
        import yaml
    except ModuleNotFoundError:
        yaml = None

    if yaml is not None:
        for path in yaml_paths:
            try:
                list(yaml.safe_load_all(path.read_text(encoding="utf-8")))
            except Exception as exc:
                failures.append(f"{path}: invalid YAML: {exc}")
    elif shutil.which("ruby"):
        result = subprocess.run(
            ["ruby", "-e", "require 'yaml'; ARGV.each { |path| YAML.load_stream(File.read(path)) }", *map(str, yaml_paths)],
            text=True,
            capture_output=True,
        )
        if result.returncode != 0:
            failures.append(f"YAML parser failed: {result.stderr.strip()}")
    else:
        for path in yaml_paths:
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if line.startswith("\t"):
                    failures.append(f"{path}:{number}: YAML indentation uses a tab")

for failure in failures:
    print(failure)
sys.exit(1 if failures else 0)
PY
}

check_repository_boundary() {
  local scan_files=()
  local local_marker_regex
  local_marker_regex="personal""Stack|en""schede|frank""furt|deploy[.]pub|/Users""/|/opt/personal""-stack|BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE"" KEY|AGE-SECRET""-KEY"
  while IFS= read -r path; do
    scan_files+=("${path}")
  done < <(find scripts tests packs examples skeletons fixtures docs schemas .github -type f | sort)

  if [[ "${#scan_files[@]}" -gt 0 ]] &&
    grep --line-number -E "${local_marker_regex}" "${scan_files[@]}"; then
    record_failure "Found consumer-local or secret marker in shared implementation files"
  fi
}

check_legacy_brand_references() {
  local scan_files=()
  local old_org old_org_lower legacy_regex
  old_org="Extra""Toast"
  old_org_lower="extra""toast"
  legacy_regex="${old_org}|${old_org_lower}|github:${old_org}|ghcr[.]io/${old_org_lower}|@${old_org_lower}|dev[.]${old_org_lower}|schemas[.]${old_org_lower}"
  while IFS= read -r path; do
    scan_files+=("${path}")
  done < <(find . -type f \
    ! -path './.git/*' \
    ! -path './CHANGELOG.md' \
    ! -path './scripts/validate-repository.sh' \
    ! -name '*.pyc' \
    | sort)

  if [[ "${#scan_files[@]}" -gt 0 ]] &&
    grep --line-number -E "${legacy_regex}" "${scan_files[@]}"; then
    record_failure "Found legacy coordinate outside historical changelog"
  fi
}

check_output_names() {
  local output_name_regex
  output_name_regex="flux-modules-platform""-blueprints|platform""Blueprints[.]platform""Blueprints"
  if grep --line-number -R -E "${output_name_regex}" README.md docs scripts tests packs examples skeletons fixtures schemas .github; then
    record_failure "Found doubled platform marker in public outputs or docs"
  fi
}

check_vault_policy_compiler() {
  local tmpdir
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/flux-modules-vault.XXXXXX")"
  trap 'rm -rf "${tmpdir}"' RETURN

  python3 scripts/vault/compile-vault-bootstrap-policy.py \
    --input fixtures/vault-bootstrap-policy/minimal-policy.yaml \
    --output "${tmpdir}/minimal.yaml" || {
      record_failure "Vault compiler failed on minimal fixture"
      return
    }

  python3 scripts/vault/compile-vault-bootstrap-policy.py \
    --input fixtures/vault-bootstrap-policy/full-policy.yaml \
    --output "${tmpdir}/full.yaml" || {
      record_failure "Vault compiler failed on full fixture"
      return
    }

  grep -q 'kind: Job' "${tmpdir}/minimal.yaml" || record_failure "Vault compiler minimal fixture did not emit a Job"
  grep -q 'kind: VaultStaticSecret' "${tmpdir}/full.yaml" || record_failure "Vault compiler full fixture did not emit a VaultStaticSecret"
  grep -q 'kind: VaultDynamicSecret' "${tmpdir}/full.yaml" || record_failure "Vault compiler full fixture did not emit a VaultDynamicSecret"
  grep -q 'rabbitmq/roles/app-rabbitmq' "${tmpdir}/full.yaml" || record_failure "Vault compiler full fixture did not emit RabbitMQ role commands"
}

check_required_paths
check_forbidden_paths
check_shell_syntax
check_python_syntax
check_json_yaml || record_failure "JSON/YAML validation failed"
check_repository_boundary
check_legacy_brand_references
check_output_names
check_vault_policy_compiler

if [[ "${#failures[@]}" -gt 0 ]]; then
  printf '%s\n' "${failures[@]}" >&2
  exit 1
fi

echo "Repository validation passed"
