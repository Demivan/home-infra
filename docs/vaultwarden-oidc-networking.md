# Vaultwarden OIDC Authority URL Problem

## Problem

Vaultwarden is deployed in Kubernetes with SSO via Authentik (also in-cluster). Vaultwarden has a single `SSO_AUTHORITY` URL setting that is used for **both**:
1. Server-side OIDC discovery (Vaultwarden pod → Authentik)
2. Browser-side redirect (user's browser → Authentik login page)

Authentik is exposed via Tailscale Ingress at `https://authentik.taild84c78.ts.net`.
Vaultwarden is exposed via Tailscale Ingress at `https://vaultwarden.taild84c78.ts.net`.

- If we use `https://authentik.taild84c78.ts.net/application/o/vaultwarden/`: the browser redirect works, but Vaultwarden pod can't resolve the Tailscale hostname (no Tailscale DNS inside pods).
- If we use `http://authentik-server.identity.svc/application/o/vaultwarden/`: OIDC discovery works server-side, but the browser gets redirected to an unresolvable internal URL.

## Current Infrastructure

- Kubernetes on Hetzner Cloud (Talos Linux), single node CX43
- CNI: Cilium (kube-proxy replacement, Gateway API enabled but no Gateway resource deployed yet)
- VPN: Tailscale operator (provides `ingressClassName: tailscale` for Ingress resources)
- DNS: Cloudflare for `demivan.me` via external-dns (watches `gateway-httproute` sources)
- TLS: cert-manager with letsencrypt-prod ClusterIssuer (DNS-01 via Cloudflare, wildcard capable)
- Authentik service: `authentik-server.identity.svc` port 80 (HTTP)
- Tailscale Ingress for Authentik terminates TLS and proxies to the service

## Constraints

- **Strongly prefer not exposing services to the public internet**
- All users access services via Tailscale tailnet
- The solution must work for both Vaultwarden's server-side OIDC calls and browser redirects

## Investigate These Solutions (in order of preference)

### 1. Tailscale DNS inside pods
Can Tailscale operator be configured so that pods can resolve Tailscale hostnames (*.taild84c78.ts.net)? Check if there's a `dnsConfig` or Tailscale nameserver injection option. This would be the cleanest fix.

### 2. CoreDNS rewrite/override
Add a custom CoreDNS entry that maps `authentik.taild84c78.ts.net` to the Authentik Tailscale proxy's ClusterIP. The Tailscale proxy pod in the identity namespace handles TLS termination, so if we route to its ClusterIP, HTTPS with the valid Tailscale cert should work. Find how to configure CoreDNS overrides on Talos Linux.

### 3. hostAliases on Vaultwarden pod
The guerzon/vaultwarden Helm chart may support `hostAliases` or `extraPodSpec` to add `/etc/hosts` entries. Map `authentik.taild84c78.ts.net` to the Tailscale proxy's ClusterIP. Downside: ClusterIP could change.

### 4. Cilium Gateway API with split-horizon DNS
Deploy a Cilium Gateway resource for `authentik.demivan.me` (or a subdomain) that's only accessible in-cluster + via Tailscale, not on the public internet. Use cert-manager for TLS. Both browser and pod use the same hostname. Check if Cilium L2/internal-only mode is possible.

### 5. Fallback: Cloudflare Tunnel ingress
If none of the above work, deploy Cloudflare Tunnel (cloudflared) as ingress for Authentik at `auth.demivan.me`. This exposes it to the internet but behind Cloudflare's proxy. Both browser and Vaultwarden pod can reach it. external-dns + cert-manager already support this domain.

## What to Report

For each viable solution:
- Exact configuration/manifests needed
- Which files in the repo to modify
- Any gotchas or downsides
- Whether it requires changes to Authentik's configuration

## Key Repo Files for Context

- `kubernetes/apps/vaultwarden/kustomization.yaml` - Vaultwarden Helm values (authority URL is here)
- `kubernetes/platform/identity/kustomization.yaml` - Authentik Helm values
- `kubernetes/platform/identity/ingress.yaml` - Authentik Tailscale Ingress
- `kubernetes/system/cilium/kustomization.yaml` - Cilium config (Gateway API enabled)
- `kubernetes/system/tailscale/kustomization.yaml` - Tailscale operator config
- `kubernetes/system/external-dns/kustomization.yaml` - external-dns config
- `kubernetes/system/cert-manager/clusterissuer.yaml` - cert-manager issuers
