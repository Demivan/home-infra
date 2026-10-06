# Stalwart mail runbook

Stalwart v0.16 keeps almost all configuration in its database. The repo holds:

- `config/config.json`: the datastore definition (RocksDB on the `stalwart-data` PVC). This is the only setting read from disk.
- `config/plan.ndjson`: everything else (domains, listeners, certificate, DKIM, relay route, MTA-STS policy, logging), reconciled by the `stalwart-apply` PostSync Job with `stalwart-cli apply`. Edit the plan, merge, and ArgoCD reapplies it. Objects of types the plan `reconcile`s (DKIM signatures, listeners, relay routes, tracers) are deleted when dropped from the plan. `upsert`ed types are never deleted by the Job.
- Accounts are **not** in the plan. They are directory data, managed through the CLI or WebUI.

| Endpoint | Exposure |
|---|---|
| SMTP 25, submissions 465, submission 587, IMAPS 993 | Public: the `stalwart-mail` LoadBalancer gets the node IP `46.224.162.75` (`mail.demivan.me`) from Cilium node IPAM |
| MTA-STS policy, 443 | Public: the `public` Cilium Gateway routes only `mta-sts.*/.well-known/mta-sts.txt` to Stalwart, which generates the policy from the `MtaSts` object in the plan |
| JMAP, WebUI `/admin`, self-service `/account` | Tailnet only: `https://mail.home.demivan.me` |

Commands below use `stalwart-cli` from the devShell against a port-forward, authenticating with `STALWART_TOKEN` (or `STALWART_USER`/`STALWART_PASSWORD`):

```bash
kubectl --context admin@homelab -n stalwart port-forward svc/stalwart 8080:8080
```

```bash
export STALWART_URL=http://localhost:8080
```

## Secrets (Infisical, `prod`, `/`)

| Key | Content | How to generate |
|---|---|---|
| `stalwart-recovery-admin-password` | Recovery admin password (username is `recovery`), no trailing newline | `openssl rand -hex 24` |
| `stalwart-dkim-s2026a-rsa` | RSA-2048 PEM private key | `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048` |
| `stalwart-dkim-s2026a-ed25519` | Ed25519 PEM private key | `openssl genpkey -algorithm ED25519` |
| `stalwart-relay-password` | Relay SMTP password. Any placeholder until a relay is chosen (the secret must exist) | From the relay provider |
| `stalwart-api-token` | API key of `postmaster@…`, used by the apply Job and the TLS reload CronJob | Created after bootstrap, see below |

Encryption at rest has no server-side secret: each user uploads their own public key (see "Encryption at rest").

Multi-line values go in with the `name=@file` form. Discard the command's output, which can include the values:

```bash
infisical secrets set --env=prod --path=/ stalwart-dkim-s2026a-rsa=@s2026a-rsa.pem >/dev/null 2>&1 && echo ok
```

## First deployment (order matters)

1. **Prerequisites before merging**
   - The Cilium change that enables node IPAM and adds the `public` Gateway is merged and synced. Without it the `stalwart-mail` LoadBalancer stays pending and the MTA-STS route has no parent.
   - Create the four Infisical keys above (everything except `stalwart-api-token`).
   - Apply the Hetzner firewall rules for 25/465/587/993 in `terraform/main.tf` through HCP Terraform. Read the plan: abort if it touches the control-plane `alias_ips`.
   - Set reverse DNS in the Hetzner Console: Server → Networking → Primary IPv4 `46.224.162.75` → `mail.demivan.me`. Do the same for the primary IPv6 if AAAA records are ever published.
2. **Merge.** `kustomization.yaml` includes the `recovery` component, so Stalwart starts in recovery mode: no mail listeners, management API on :8080 only.
   - Sync `external-dns` before `stalwart`, because the DNSEndpoint CRD comes from the external-dns app. If `stalwart` synced first and failed on the DNSEndpoint, sync it again.
   - The `stalwart-apply` PostSync Job loads the plan as the recovery admin. Check it with `kubectl -n stalwart logs job/stalwart-apply`.
3. **Create the admin account** while still in recovery mode, signing in as the recovery admin. Store the password in Vaultwarden.

   ```bash
   STALWART_USER=recovery STALWART_PASSWORD=<recovery password> stalwart-cli query Domain
   ```

   ```bash
   STALWART_USER=recovery STALWART_PASSWORD=<recovery password> stalwart-cli create Account/User --json '{"name":"postmaster","domainId":"<lab domain id>","roles":{"@type":"Admin"},"credentials":{"0":{"@type":"Password","secret":"<password>"}}}'
   ```
4. **Leave recovery mode.** Remove `components: [recovery]` from `kustomization.yaml` and merge. The pod restarts with the mail ports live.
   - The sync waits for the `stalwart-api` ExternalSecret, which can't resolve until step 5.
5. **Create the API key** as postmaster. This requires normal mode; recovery mode answers 403. Store the secret in Infisical as `stalwart-api-token`. Once ESO picks it up (hourly refresh), the pending sync runs the apply Job with the key.

   ```bash
   STALWART_USER=postmaster@lab.demivan.me STALWART_PASSWORD=<password> stalwart-cli create ApiKey --json '{"description":"argocd stalwart-apply","permissions":{"@type":"Inherit"}}'
   ```
6. Add the **staging DNS records** below and run the **verification checklist** against `lab.demivan.me`.
7. Configure the **relay**, then repeat the outbound checks.
8. **Cut over** `demivan.me`.

`STALWART_RECOVERY_ADMIN` is a backdoor credential. It is only set while the `recovery` component is included; re-add the component for maintenance or lock-out recovery.

## DNS records

external-dns creates `A mail.demivan.me` from `dnsendpoint.yaml`, and `A mta-sts.lab.demivan.me` / `A mta-sts.demivan.me` from the `mta-sts` HTTPRoute (the public Gateway's address). All are `46.224.162.75`. Add everything else by hand in Cloudflare, with proxying **off** (DNS only).

DKIM `p=` values come from the private keys. These commands produce the same values Stalwart prints with `stalwart-cli get Domain <id> --fields dnsZoneFile`:

```bash
openssl pkey -in s2026a-rsa.pem -pubout -outform DER | openssl base64 -A
```

```bash
openssl pkey -in s2026a-ed25519.pem -pubout -outform DER | tail -c 32 | openssl base64 -A
```

The `_mta-sts` id is Stalwart's. It is stable across restarts and changes whenever the `MtaSts` object changes, which is what tells senders to refetch the policy. After any `MtaSts` change, copy the new value into the TXT record:

```bash
stalwart-cli get Domain <id> --fields dnsZoneFile | grep _mta-sts
```

### Staging: `lab.demivan.me`

| Type | Name | Value |
|---|---|---|
| MX | `lab.demivan.me` | `10 mail.demivan.me` |
| TXT | `lab.demivan.me` | `v=spf1 include:<RELAY_SPF_DOMAIN> ~all` (`v=spf1 -all` until a relay exists) |
| TXT | `s2026a-rsa._domainkey.lab.demivan.me` | `v=DKIM1; k=rsa; p=<rsa p>` |
| TXT | `s2026a-ed._domainkey.lab.demivan.me` | `v=DKIM1; k=ed25519; p=<ed25519 p>` |
| TXT | `_dmarc.lab.demivan.me` | `v=DMARC1; p=none; rua=mailto:postmaster@lab.demivan.me` |
| TXT | `_mta-sts.lab.demivan.me` | `v=STSv1; id=<id from the zone file>` |
| TXT | `_smtp._tls.lab.demivan.me` | `v=TLSRPTv1; rua=mailto:postmaster@lab.demivan.me` |
| SRV | `_submissions._tcp.lab.demivan.me` | `0 1 465 mail.demivan.me` |
| SRV | `_submission._tcp.lab.demivan.me` | `0 1 587 mail.demivan.me` |
| SRV | `_imaps._tcp.lab.demivan.me` | `0 1 993 mail.demivan.me` |
| SRV | `_jmap._tcp.lab.demivan.me` | `0 1 443 mail.home.demivan.me` (resolves to a tailnet-only service) |
| SRV | `_imap._tcp.lab.demivan.me`, `_pop3._tcp…`, `_pop3s._tcp…` | `0 0 0 .` ("not offered", RFC 6186) |

### Production: `demivan.me` (only at cutover)

The same set with `lab.` removed, plus these changes to existing records:

- **MX:** `demivan.me` currently points at Cloudflare Email Routing (`*.mx.cloudflare.net`). Disable Email Routing in the Cloudflare dashboard, because it owns those MX records. Then add `10 mail.demivan.me`.
- **SPF:** replace `v=spf1 include:_spf.mx.cloudflare.net ~all` with `v=spf1 include:<RELAY_SPF_DOMAIN> ~all`.
- **DMARC:** keep the existing `_dmarc.demivan.me` (`p=none`, rua to Gmail). Optionally add `mailto:postmaster@demivan.me` to `rua`. Tighten to `p=quarantine` once reports are clean.
- **MTA-STS:** add `_mta-sts.demivan.me` only at cutover. Publishing it while MX still points at Cloudflare would contradict the policy.

### Optional: DANE

1. Enable DNSSEC on the zone in Cloudflare.
2. Publish `TLSA _25._tcp.mail.demivan.me 3 1 1 <hash>`, where `<hash>` comes from the command below. The certificate's key doesn't rotate (`rotationPolicy: Never`), so the record survives renewals.

```bash
kubectl -n stalwart get secret stalwart-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -hex
```

## Relay

Until a relay is configured, the `relay` route in `config/plan.ndjson` points at `127.0.0.1:9`. Connections there are refused, so outbound mail **stays queued** and is retried. Senders get a delay DSN after 1 day, and messages expire (bounce) after about 3 days. Don't use an unresolvable placeholder hostname: NXDOMAIN on the relay host counts as a permanent failure and bounces immediately.

To configure a relay:

1. In `plan.ndjson`, set `address`, `port` (587, STARTTLS, so `implicitTls: false`) and `authUsername` on the `relay` route.
2. Set `stalwart-relay-password` in Infisical.
3. Put the provider's SPF include in the SPF records.
4. If the provider requires domain verification, add its records too. DKIM signing stays ours (`s2026a-*`).

## Adding a user

Users are created with the CLI (or WebUI → Management → Accounts at `https://mail.home.demivan.me/admin`):

```bash
stalwart-cli query Domain
```

```bash
stalwart-cli create Account/User --json '{"name":"ivan","domainId":"<domain id>","credentials":{"0":{"@type":"Password","secret":"<initial password>"}}}'
```

The user then signs in at `https://mail.home.demivan.me/account` to change the password, add app passwords for mail clients, and set up encryption at rest.

Client settings: IMAP `mail.demivan.me:993` (TLS) and SMTP `mail.demivan.me:465` (TLS) or `:587` (STARTTLS), username = full email address. JMAP: `https://mail.home.demivan.me/.well-known/jmap` (tailnet only).

## Encryption at rest (per user)

The server-wide `encryptAtRest` flag is on in the plan. Each user turns it on for their own account:

1. Generate a key pair on the client, for example `gpg --quick-gen-key "Name <user@domain>" ed25519 default never` followed by `gpg --quick-add-key <fpr> cv25519 encr never`. Alternatively use an S/MIME certificate.
2. Self-service portal → Public Keys: upload `gpg --armor --export user@domain`. Then Settings → Encryption at rest: AES-256 with that key.
3. Import the private key into Thunderbird (OpenPGP) or another client that can decrypt.

Same thing from the CLI, signed in as the user:

```bash
stalwart-cli create PublicKey --json '{"description":"laptop","key":"<armored public key>","emailAddresses":{"user@domain":true}}'
```

```bash
stalwart-cli update AccountSettings --json '{"encryptionAtRest":{"@type":"Aes256","publicKey":"<key id>","encryptOnAppend":false,"allowSpamTraining":false}}'
```

Consequences:
- Only mail delivered **after** enabling is encrypted.
- Bodies and attachments are stored as PGP/MIME; headers, including Subject, stay readable.
- The server cannot full-text search bodies.
- Webmail and JMAP clients without the key can't render the body.
- Losing the private key loses the mail.

## Rotating DKIM

Selectors are named `s<year><letter>-{rsa,ed}`.

1. Generate the new keys and store them in Infisical as `stalwart-dkim-s2027a-rsa` and `stalwart-dkim-s2027a-ed25519`.
2. Publish the new `s2027a-*._domainkey` TXT records for every domain and wait for propagation.
3. In one PR:
   - Add the new keys to the `stalwart-dkim` ExternalSecret.
   - Add `s2027a` entries to the `DkimSignature` line in `plan.ndjson`, and remove the `s2026a` entries. The Job's `reconcile` deletes the old signatures.
4. Keep the old `s2026a` TXT records for about 7 days so mail in flight still verifies. Then delete the records, the Infisical keys, and the ExternalSecret entries.

## Outbound queue

```bash
stalwart-cli query QueuedMessage
```

```bash
stalwart-cli get QueuedMessage <id>
```

```bash
stalwart-cli update QueuedMessage <id> --field nextRetry=<RFC3339 time>
```

```bash
stalwart-cli delete QueuedMessage --ids <id>
```

```bash
stalwart-cli create Action/PauseMtaQueue
```

```bash
stalwart-cli create Action/ResumeMtaQueue
```

- `get` shows the retry count and next-notification time per recipient.
- `update … nextRetry` reschedules a delivery attempt.
- `delete` drops a message without a bounce.
- Pause/resume stops and restarts outbound delivery, for example while changing relays.
- Delivery errors are in the pod log: `kubectl -n stalwart logs deploy/stalwart | grep -E 'delivery\.|queue\.'`.

## Verification checklist

Run against `lab.demivan.me` first; repeat the inbound/outbound items for `demivan.me` after cutover.

- [ ] `nc -vz mail.demivan.me 25` (and 465, 587, 993) from outside the tailnet. `openssl s_client -starttls smtp -connect mail.demivan.me:25` shows the Let's Encrypt cert for `mail.demivan.me`.
- [ ] Banner/EHLO reply is `mail.demivan.me`, and `dig -x 46.224.162.75` returns `mail.demivan.me`.
- [ ] Received header of an inbound message shows the real sender IP, not a cluster address (`externalTrafficPolicy: Local` on `stalwart-mail` keeps client IPs).
- [ ] Inbound from Gmail and from Outlook.com reaches the INBOX (`Authentication-Results` shows spf/dkim/dmarc pass).
- [ ] Outbound to Gmail and Outlook.com via the relay. In the received message, `DKIM-Signature` headers with `d=lab.demivan.me; s=s2026a-rsa` and `s=s2026a-ed` verify (Gmail "Show original": DKIM PASS with `lab.demivan.me`), alongside any relay signature.
- [ ] mail-tester.com: send via the relay and reach 10/10.
- [ ] Thunderbird: IMAP login on 993 and send on 465/587 with autoconfig via SRV records.
- [ ] JMAP: `curl -u user@lab.demivan.me https://mail.home.demivan.me/.well-known/jmap -L` returns a session object (tailnet).
- [ ] `curl https://mta-sts.lab.demivan.me/.well-known/mta-sts.txt` returns the policy; `curl https://mta-sts.lab.demivan.me/admin` and `curl -k --resolve mail.demivan.me:443:46.224.162.75 https://mail.demivan.me/` return 404 from the gateway.
- [ ] Failure handling: with the relay unreachable (the placeholder), a submitted message stays in `query QueuedMessage` with a growing retry count rather than bouncing. Unknown local recipients get `550 5.1.2` at RCPT time (intended permanent rejection, not a bounce later).
- [ ] Encryption at rest: after enabling it for a test user, a newly delivered message fetched over IMAP is `multipart/encrypted`.
- [ ] Backup: next morning, `kubectl -n stalwart get backups.k8up.io` shows a completed run.

## Cutover (`demivan.me`)

1. Check Cloudflare Email Routing rules and create matching accounts or aliases in Stalwart; every forwarded address must exist before MX moves.
2. In `plan.ndjson`:
   - Add a `demivan.me` entry to the `Domain` upsert.
   - Add `s2026a-rsa` and `s2026a-ed` `DkimSignature` entries for it (same key files, `domainId` `#<new domain ref>`).
   - Point `SystemSettings.defaultDomainId` at it.
3. Publish the production DNS records, disable Email Routing, and switch MX.
4. Re-run the checklist for `demivan.me`. After a week of clean DMARC/TLS-RPT reports, consider `"mode": "enforce"` on the `MtaSts` line of `plan.ndjson` (then update the `_mta-sts` id) and a stricter DMARC policy.

## Operational notes

- **Resources:** request 256Mi / 50m CPU, limit 1Gi. Measured about 140–160Mi idle. RocksDB caches are capped in `config.json` (64Mi block cache, 32Mi write buffers). Tune from `container_memory_working_set_bytes`.
- **Startup egress:** Stalwart downloads its WebUI bundle and ASN/geo data from GitHub at startup, and spam-filter rule updates on a schedule. If GitHub is unreachable, the WebUI may be missing, but mail still flows.
- **Backups:** the `stalwart-data` PVC is covered by the k8up `backup` Schedule (restic → B2, nightly 03:45). It is a file-level copy of a live RocksDB directory, not an application-consistent snapshot. See the follow-up below.
- **The node IP is pinned** in `dnsendpoint.yaml`. Recreating the server (new IP) requires updating it, the PTR, and every relay or allowlist entry.

## Follow-ups

- Application-consistent backups: a k8up `k8up.io/backupcommand` pre-backup hook, or a nightly `stalwart-cli snapshot` export plus a RocksDB checkpoint. Restore has not been tested.
- Authentik OIDC for Stalwart (out of scope for the first pass).
