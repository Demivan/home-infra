# Homelab Infrastructure

Personal Kubernetes homelab on Hetzner Cloud, managed with OpenTofu + Talos Linux + ArgoCD.

## Architecture

- **Compute:** 1x Hetzner CX43 (8 x86 vCPU / 16GB RAM), Falkenstein (`fsn1`), Talos Linux
- **Networking:** Cilium (CNI + kube-proxy replacement), Tailscale (VPN mesh). Gateway API enabled when ArgoCD manages Cilium.
- **Storage:** Hetzner CSI (dynamic PVs), Storage Box BX11 (1TB HDD) for bulk data via NFS
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
├── terraform/
│   ├── main.tf              # HCP backend + hcloud-talos module (network, firewall, server, Talos bootstrap, Cilium, CCM)
│   ├── talos-image.tf       # Talos image factory schematic + imager upload
│   ├── variables.tf         # hcloud_token, server_type, location, talos/k8s versions
│   └── outputs.tf           # server IP, network ID, talosconfig, kubeconfig
├── kubernetes/
│   ├── bootstrap/           # ArgoCD initial Helm values
│   ├── root-app.yaml        # App-of-apps root Application
│   ├── system/              # cilium, cert-manager, external-dns, argocd, cnpg,
│   │                        # authentik, eso, velero, monitoring, tailscale,
│   │                        # hetzner-ccm, hetzner-csi
│   └── apps/                # immich, ocis, vaultwarden, radicale, minecraft
├── docs/                    # Architecture docs, plans
└── flake.nix                # devShell + upload-talos-image package
```

## Key Conventions

- **OpenTofu** (not Terraform) for all infrastructure provisioning
- **x86_64 (amd64)** — switched from ARM due to availability/pricing
- **FOSS preferred** throughout; exceptions: Hetzner, Backblaze B2, HCP (Vault Secrets + Terraform)
- **Gateway API** (HTTPRoute + TCPRoute) — no Ingress API, no Traefik
- **Hetzner CSI** for dynamic volume provisioning; static NFS PVs for Storage Box mounts
- **Sync waves** in ArgoCD: Wave 0 (Cilium, CCM/CSI) → Wave 1 (cert-manager, external-dns, ESO, CNPG) → Wave 2 (Authentik + Redis + PG) → Wave 3 (apps)
- **Priority classes:** infra-critical (Cilium, CCM/CSI) > platform (ArgoCD, Authentik, cert-manager) > app-default (Immich, oCIS, etc.) > best-effort (Minecraft)
- **Talos image extensions:** qemu-guest-agent, nfs-utils, iscsi-tools — baked via Image Factory schematic
- **hcloud-talos module** (v3) manages Hetzner infra + Talos bootstrap + initial Cilium/CCM deploy
- **HCP Terraform** runs apply remotely — `firewall_use_current_ip` doesn't work, use explicit source CIDRs
- **Immich ML** needs explicit resource limits to avoid starving other pods during photo import
- Secrets never in git — all via ESO + Infisical
- Do not commit without user review
