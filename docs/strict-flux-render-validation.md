# Strict Flux Render Validation

Strict Flux render validation checks the manifests a Flux tree produces before
they reach a cluster:

1. `kustomize build` for every supplied overlay.
2. `flux build kustomization` for the same overlays.
3. `kubeconform` against Kubernetes schemas plus an explicit pinned CRD schema
   catalog.

## One-Job Adoption

Add a job that calls the reusable workflow from
`JorisJonkers-dev/github-workflows`:

```yaml
jobs:
  flux-render-validate:
    uses: JorisJonkers-dev/github-workflows/.github/workflows/flux-render-validate.yml@v0.6.0
    with:
      overlay-paths: |
        path/to/flux/overlay
      mode: strict
      crd-catalog-source: JorisJonkers-dev/flux-modules
      crd-catalog-ref: v1.1.0
```

The reusable workflow checks out the caller repository, installs pinned
`kustomize`, `flux`, and `kubeconform`, checks out the pinned CRD catalog, and
runs `scripts/validate-flux-render.sh` with one `--overlay` argument per line.

## Local Use

```sh
scripts/validate-flux-render.sh \
  --overlay path/to/flux/overlay \
  --mode strict
```

Use `--mode lenient` to omit kubeconform's `-strict` flag while still rendering
the overlays and requiring CRD schemas to resolve.

## CRD Schema Pinning

The default catalog lives in `schemas/crds` and is pinned as of 2026-06-10. It
contains explicit JSON schema files for Flux, cert-manager, Traefik, and Vault
Secrets Operator resources emitted by platform packs. The script maps a catalog
directory to kubeconform with this template:

```text
<catalog>/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json
```

Pass `--crd-catalog <dir>` to use another local catalog, or
`--crd-schema-location <location>` for an exact kubeconform schema location.

Repository-template opt-in is intentionally left as a follow-up.
