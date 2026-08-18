# flux-modules

Reusable Kubernetes, Flux, storage, edge, CRD schema, backup, restore, and
validation blueprints for JorisJonkers-dev platform repositories.

## Consumer Boundary

This repository is a shared platform artifact, not a deployable environment. It
may contain:

- Flux and Kubernetes packs with substitution placeholders.
- A pinned CRD schema catalog for offline render validation.
- Validation scripts that operate on caller-owned paths.
- Backup, restore, and Vault bootstrap tooling that takes caller-owned inputs.
- Gateway API preview and Longhorn storage packs with only placeholder values.
- Documentation, examples, tests, CI, and release metadata for this artifact.

Reusable host modules and Nix helpers live in
`JorisJonkers-dev/nixos-modules`. Consumer repositories continue to own host
configuration, deploy nodes, inventories, secrets, app manifests, generated
manifests, locks, and deployment workflows.

Do not add private keys, token values, inventory files, application manifests,
rendered Flux output, Nomad jobs, Consul jobs, or consumer host data to this
repository.

## Flux Packs

Reusable parameterized packs live under:

- `packs/flux-core`: cert-manager, external-dns, Traefik public/LAN, MetalLB,
  and VSO bases.
- `packs/edge`: Cloudflare ClusterIssuer, default TLSStore, and forward-auth
  middleware.
- `packs/edge-middleware`: Traefik forward-auth, response/security headers,
  named CSP profiles, default public middleware chains, local certificate
  file-provider config, and dashboard exposure.
- `packs/gateway-api-preview`: GatewayClass and public/LAN Gateway templates
  for preview route rendering.
- `packs/longhorn-site-storage`: Longhorn Helm release, retained StorageClass,
  and recurring job templates for consumer-owned storage adoption plans.
- `packs/rabbitmq-data-service`: RabbitMQ Helm release, OAuth2 management
  config, VSO internal credentials, ServiceMonitor, storage, and placement.
- `packs/observability`: metrics, Grafana, Loki, Tempo, Alloy, Gatus, alerts,
  and optional profiling/GPU telemetry.

The manifests use substitution placeholders. Consumers provide namespaces,
domains, ACME emails, token secret names, storage sizes, node selectors,
forward-auth endpoints, and component choices through their own Flux
`postBuild.substitute`, kustomize replacements, or renderer. Application
IngressRoutes, service-specific dashboards, and Gatus endpoint ConfigMaps stay
in consumer repositories.

## Validation Scripts

Validate this repository boundary and offline fixtures:

```bash
bash scripts/validate-repository.sh
bash tests/scripts/backup-tooling-smoke.sh
bash tests/scripts/restore-tooling-smoke.sh
bash tests/scripts/flux-render-validation-smoke.sh
```

Validate a rendered Flux overlay with the bundled CRD catalog:

```bash
scripts/validate-flux-render.sh \
  --overlay tests/fixtures/flux-render-good \
  --crd-catalog schemas/crds \
  --mode strict
```

Validate a caller-owned Flux tree:

```bash
scripts/validate-flux.sh \
  --flux-root ./cluster/flux \
  --cluster-path ./cluster/flux/clusters/production \
  --apps-path ./cluster/flux/apps \
  --offline
```

Run caller-owned render commands and fail if generated files drift:

```bash
scripts/validate-platform-render.sh \
  --repo-root "$PWD" \
  --render-command-file ./render-commands.txt \
  --generated-path-file ./generated-paths.txt
```

## Vault Bootstrap

Compile a Vault bootstrap policy model into manifests:

```bash
python3 scripts/vault/compile-vault-bootstrap-policy.py \
  --input fixtures/vault-bootstrap-policy/full-policy.yaml \
  --output /tmp/vault-bootstrap.generated.yaml
```

The generated bootstrap Job contains live-only Vault CLI commands. Apply it
only after the target cluster has Vault, VSO CRDs, and a bootstrap token Secret.

## Backup And Restore

List and dry-run a manifest-driven remote filesystem backup:

```bash
scripts/backup/backup-service-state.sh \
  --manifest examples/backup/manifest.tsv \
  --output-dir /tmp/flux-modules-backup \
  --dry-run
```

Capture service-native snapshot plugins declared by the consumer:

```bash
scripts/backup/backup-service-snapshots.sh \
  --plugins examples/backup/snapshot-plugins.tsv \
  --output-dir /tmp/flux-modules-snapshots \
  --dry-run
```

Verify and restore runs with the scripts under `scripts/backup` and
`scripts/restore`. Snapshot plugin commands are caller-owned executables. This
repository does not embed Vault, Consul, Nomad, RabbitMQ, host paths, or
credential lookup commands.

Service-native restore primitives include:

- `scripts/restore/restore-vault-raft-snapshot.sh`
- `scripts/restore/restore-http-api-export.sh`

Sanitized example playbooks live under `docs/runbooks`.

## Skeleton Models

Working packs and tooling are supported by input-model examples:

- `skeletons/edge-middleware`
- `skeletons/rabbitmq-data-service`
- `skeletons/vault-bootstrap-policy`
- `fixtures/vault-bootstrap-policy`
- `docs/runbooks`
- `docs/dns-zone-policy.md`

These examples are not inventories, rendered output, or live secret material.

## Versioning

Releases are managed with release-please. Consumers should pin an exact tag or
locked revision and let Renovate propose updates in their own repository. Each
consumer can review and advance the shared platform version independently.

## Links

- [Organization profile](https://github.com/JorisJonkers-dev)
- [Security policy](https://github.com/JorisJonkers-dev/.github/security/policy)
- [Changelog](./CHANGELOG.md)
- [License](./LICENSE)

Copyright (c) Joris Jonkers. Source available for viewing only; use, copying,
modification, redistribution, deployment, or reuse is not licensed. See
[LICENSE](./LICENSE).
