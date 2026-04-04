# Homelab Infrastructure

Personal Kubernetes homelab on Hetzner Cloud, managed with OpenTofu + Talos Linux + ArgoCD.

## Architecture

- **Compute:** 1x Hetzner CX43 (8 x86 vCPU / 16GB RAM), Falkenstein (`fsn1`), Talos Linux
- **Networking:** Cilium (CNI + kube-proxy replacement), Tailscale (VPN mesh), Gateway API CRDs (standard channel v1.2.1)
- **Internal DNS:** Split-horizon via `*.home.demivan.me` — CoreDNS rewrites to Cilium Gateway (NodePort), Tailscale Split DNS + Connector for tailnet client access
- **Storage:** Hetzner CSI (dynamic PVs), Storage Box BX11 (1TB HDD, Terraform-managed) for bulk data via NFS
- **Backup:** Velero (PVC snapshots) + Rustic (Storage Box data) → Backblaze B2
- **Secrets:** Infisical → External Secrets Operator (Kubernetes Auth) → K8s Secrets. Also Infisical Terraform provider for OpenTofu secrets.
- **State:** HCP Terraform (free tier) — remote state with locking
- **Identity:** Authentik (SSO via OIDC/LDAP for all services)
- **GitOps:** ArgoCD with ApplicationSet (git directory generator), Kustomize + helmCharts
- **DNS/TLS:** Cloudflare (demivan.me) via external-dns + cert-manager (DNS-01 wildcard)
- **Monitoring:** VictoriaMetrics + Grafana
- **Updates:** Renovate Bot on GitHub

## Applications

| Service | Purpose | Auth | URL |
|---|---|---|---|
| Authentik | SSO/Identity (OIDC/LDAP) | — | `auth.home.demivan.me` |
| Vaultwarden | Password manager | OIDC | `vault.home.demivan.me` |
| ArgoCD | GitOps | — | `argocd.home.demivan.me` |
| Immich | Google Photos replacement | OIDC | |
| oCIS | Google Drive replacement | OIDC | |
| Radicale | Calendar/Contacts (CalDAV/CardDAV) | LDAP | |
| Minecraft GTNH | Game server (Tailscale-only) | N/A | |

## Repo Structure

```
infra/
├── terraform/
│   ├── main.tf              # HCP backend + hcloud-talos module + Infisical provider + Storage Box
│   ├── talos-image.tf       # Talos image factory schematic + imager upload
│   ├── variables.tf         # server_type, location, talos/k8s versions (secrets from Infisical)
│   └── outputs.tf           # server IP, network ID, talosconfig, kubeconfig, storagebox
├── kubernetes/
│   ├── bootstrap/           # ArgoCD initial Helm values
│   ├── root-app.yaml        # Points to kubernetes/system/, applies ApplicationSet
│   ├── system/              # Each subdirectory = one ArgoCD Application (auto-discovered)
│   │   ├── applicationset.yaml  # Git directory generator for system/*
│   │   ├── argocd/          # ArgoCD self-management
│   │   ├── cilium/          # Cilium + Gateway API CRDs + cilium-internal GatewayClass
│   │   ├── cilium-gateway/  # Gateway + wildcard cert for *.home.demivan.me
│   │   ├── cert-manager/    # cert-manager + ClusterIssuers + ExternalSecret
│   │   ├── external-dns/    # external-dns + ExternalSecret
│   │   ├── external-secrets/ # ESO + Infisical ClusterSecretStore
│   │   ├── hetzner-ccm/     # Hetzner CCM + ExternalSecret
│   │   ├── hetzner-csi/     # Hetzner CSI driver
│   │   ├── cnpg-system/     # CloudNativePG operator
│   │   ├── tailscale/       # Tailscale operator + ExternalSecret + Connector (subnet router)
│   │   └── common/          # Priority classes
│   └── apps/                # immich, ocis, vaultwarden, radicale, minecraft
├── docs/                    # Architecture docs, plans
└── flake.nix                # devShell (opentofu, talosctl, kubectl, helm, kustomize, etc.)
```

## Key Conventions

- **OpenTofu** (not Terraform) for all infrastructure provisioning
- **x86_64 (amd64)** — switched from ARM due to availability/pricing
- **FOSS preferred** throughout; exceptions: Hetzner, Backblaze B2, HCP Terraform
- **Kustomize + helmCharts** — each component is a kustomization.yaml with `helmCharts:` for upstream charts and `resources:` for extra manifests. No wrapper Helm charts.
- **ApplicationSet** (git directory generator) — auto-discovers `kubernetes/system/*` directories. Folder name = namespace (`CreateNamespace=true`). No per-app Application manifests needed.
- **Gateway API** (HTTPRoute) — no Ingress API, no Traefik. CRDs managed in Cilium kustomization.
- **`cilium-internal` GatewayClass** — NodePort-backed (no Hetzner LB), used for all internal services via `*.home.demivan.me`
- **Split-horizon DNS** — CoreDNS rewrites `*.home.demivan.me` → `cilium-gateway-internal.cilium-gateway.svc.cluster.local`. Tailscale Connector advertises service CIDR `10.0.8.0/21`. Tailscale Split DNS (admin console) sends `home.demivan.me` queries to CoreDNS at `10.0.8.10`.
- **Hetzner CSI** for dynamic volume provisioning; static NFS PVs co-located with apps that need them
- **ExternalSecrets co-located with consumers** — each component owns its ExternalSecret, not centralized
- **Priority classes:** infra-critical (Cilium, CCM/CSI) > platform (ArgoCD, Authentik, cert-manager) > app-default (Immich, oCIS, etc.) > best-effort (Minecraft)
- **Talos image extensions:** qemu-guest-agent, nfs-utils, iscsi-tools — baked via Image Factory schematic
- **hcloud-talos module** (v3) manages Hetzner infra + Talos bootstrap + initial Cilium/CCM deploy
- **HCP Terraform** runs apply remotely — `firewall_use_current_ip` doesn't work, use explicit source CIDRs
- **Infisical** for all secrets — K8s Auth for ESO, Universal Auth (env vars) for Terraform
- **Server-side diff** enabled in ArgoCD (`controller.diff.server.side: "true"`)
- **Immich ML** needs explicit resource limits to avoid starving other pods during photo import
- Secrets never in git — all via ESO + Infisical
- Do not commit without user review
