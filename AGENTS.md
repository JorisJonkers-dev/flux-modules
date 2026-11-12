# Agents

Guidance for any coding agent working in this repository.

The repository's agent contract is [CLAUDE.md](CLAUDE.md). The estate-wide conventions (labels, traps) are in the [estate contract](https://github.com/JorisJonkers-dev/workspace/blob/main/CLAUDE.md); read both before non-trivial changes.

This is a shared platform artifact, not a deployable environment: Flux and Kubernetes packs (`packs`), a CRD schema catalog (`schemas`), and validation, backup and restore tooling (`scripts`). See `README.md`.

## Build and test

- `bash scripts/validate-repository.sh` validates the repository.
- `bash tests/scripts/backup-tooling-smoke.sh`, `bash tests/scripts/restore-tooling-smoke.sh` and `bash tests/scripts/flux-render-validation-smoke.sh` run the smoke tests.
