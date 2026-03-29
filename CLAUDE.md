# Homelab Infrastructure

Personal Kubernetes homelab on Hetzner Cloud, managed with OpenTofu + Talos Linux + ArgoCD.

## Architecture

- **Compute:** 1x Hetzner CAX31 (8 ARM vCPU / 16GB RAM), Helsinki (`hel1`), Talos Linux
- **Networking:** Cilium (CNI + kube-proxy replacement + Gateway API), Tailscale (VPN mesh)
- **Storage:** Hetzner Volume (30GB SSD) for DBs + fast I/O, Storage Box BX11 (1TB HDD) for bulk data via NFS
- **Backup:** Velero (PVC snapshots) + Rustic (Storage Box data) → Backblaze B2
- **Secrets:** HCP Vault Secrets (free tier) → External Secrets Operator → K8s Secrets
- **State:** HCP Terraform (free tier) — remote state with locking
- **Identity:** Authentik (SSO via OIDC/LDAP for all services)
- **GitOps:** ArgoCD (app-of-apps with sync waves)
- **DNS/TLS:** Cloudflare (demivan.me) via external-dns + cert-manager (DNS-01 wildcard)
- **Monitoring:** VictoriaMetrics + Grafana
- **Updates:** Renovate Bot on GitHub

## Applications

| Service | Purpose | Auth |
|---|---|---|
| Immich | Google Photos replacement | OIDC |
| oCIS | Google Drive replacement | OIDC |
| Radicale | Calendar/Contacts (CalDAV/CardDAV) | LDAP |
| Vaultwarden | Password manager | OIDC |
| Minecraft GTNH | Game server (Tailscale-only) | N/A |

## Repo Structure

```
infra/
├── terraform/           # Hetzner resources (node, network, volume, firewall)
├── talos/               # Talos machine configs + patches
├── kubernetes/          # ArgoCD app-of-apps
│   ├── system/          # cilium, cert-manager, external-dns, argocd, cnpg,
│   │                    # authentik, eso, velero, monitoring, tailscale,
│   │                    # hetzner-ccm, hetzner-csi
│   └── apps/            # immich, ocis, vaultwarden, radicale, minecraft
├── docs/                # Architecture docs, plans, test plans
└── flake.nix            # devShell
```

## Key Conventions

- **OpenTofu** (not Terraform) for all infrastructure provisioning
- **ARM64 (aarch64)** — all container images must support linux/arm64
- **FOSS preferred** throughout; exceptions: Hetzner, Backblaze B2, HCP (Vault Secrets + Terraform)
- **Gateway API** (HTTPRoute + TCPRoute) — no Ingress API, no Traefik
- **Static NFS PVs** for Storage Box mounts (per-app subpaths), not dynamic provisioner
- **Sync waves** in ArgoCD: Wave 0 (Cilium, CCM/CSI) → Wave 1 (cert-manager, external-dns, ESO, CNPG) → Wave 2 (Authentik + Redis + PG) → Wave 3 (apps)
- **Priority classes:** system-critical (Cilium, CCM/CSI) > platform (ArgoCD, Authentik, cert-manager) > app-default (Immich, oCIS, etc.) > best-effort (Minecraft)
- **Talos NFS extension** required for NFSv4 Storage Box mounts — include in machine config
- **Immich ML** needs explicit resource limits to avoid starving other pods during photo import
- Secrets never in git — all via ESO + HCP Vault Secrets
- Do not commit without user review
