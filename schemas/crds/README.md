# Pinned CRD Schema Catalog

This catalog is the offline default used by `scripts/validate-flux-render.sh`.
It pins the CRD groups that flux-modules commonly emits so kubeconform
does not need to fetch CRD schemas during validation.

Pin date: 2026-06-10

Schema naming follows kubeconform's template:

```text
schemas/crds/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json
```

The bundled CRD schemas are intentionally minimal compatibility schemas. They
require the Kubernetes resource envelope (`apiVersion`, `kind`, and `metadata`)
and allow provider-specific `spec` fields to vary by controller version. Core
Kubernetes resources still validate against kubeconform's pinned built-in
`default` schema location.

Catalog entries:

- `cert-manager.io/Certificate_v1.json`
- `gateway.networking.k8s.io/GatewayClass_v1.json`
- `gateway.networking.k8s.io/Gateway_v1.json`
- `gateway.networking.k8s.io/HTTPRoute_v1.json`
- `gateway.networking.k8s.io/ReferenceGrant_v1beta1.json`
- `helm.toolkit.fluxcd.io/HelmRelease_v2.json`
- `kustomize.toolkit.fluxcd.io/Kustomization_v1.json`
- `longhorn.io/RecurringJob_v1beta2.json`
- `longhorn.io/Setting_v1beta2.json`
- `secrets.hashicorp.com/VaultAuth_v1beta1.json`
- `secrets.hashicorp.com/VaultConnection_v1beta1.json`
- `secrets.hashicorp.com/VaultDynamicSecret_v1beta1.json`
- `secrets.hashicorp.com/VaultStaticSecret_v1beta1.json`
- `source.toolkit.fluxcd.io/HelmRepository_v1.json`
- `traefik.io/IngressRoute_v1alpha1.json`
- `traefik.io/Middleware_v1alpha1.json`
- `traefik.io/ServersTransport_v1alpha1.json`
- `traefik.io/TLSOption_v1alpha1.json`
