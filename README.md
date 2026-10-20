# lesson-bicep-private-storage

[![validate](https://github.com/benceroth/lesson-bicep-private-storage/actions/workflows/validate.yml/badge.svg)](https://github.com/benceroth/lesson-bicep-private-storage/actions/workflows/validate.yml)

**The question this repo answers:** *My storage account has a private endpoint and an NSG. Is it actually private, and how would I prove it?*

**After working through it you can:** design the allowed flow first, deploy the private path with Bicep, and verify both what can connect and what cannot, including the DNS answer. An NSG is not a complete security design, a private endpoint does not close the public endpoint, and DNS is part of the security path. Each of those three claims has a working template and a deliberately broken variant.

Companion to the article *Stop Exposing Azure Storage: Secure It With Bicep* ([read it on Medium](https://medium.com/@benceroth/secure-networking-with-bicep-automating-azure-network-security-ca9c2f621583)). Harbor Ledger is a fictional company; all names and addresses are samples.

## Run it in two minutes (free, offline)

Needs only the Azure CLI. No Azure login, no subscription.

```powershell
az bicep install --version v0.45.15
az bicep build --file main.bicep
az bicep lint  --file main.bicep
./verify/checklist.ps1             # pass/fail checklist for main.bicep
./break-it/run-break-it.ps1       # every broken case must be CAUGHT
./verify/static-check.ps1          # compiles main + 3 variants, asserts which controls each declares
```

`static-check.ps1` prints a control matrix and exits non-zero if any template does not match its expected control set. This is exactly what CI runs (plus PSRule for Azure and an advisory Checkov scan; see `policy/`).

What the offline check proves: **the template declares the control** (e.g. `publicNetworkAccess: Disabled`, a DNS zone group, the NSG rules). What it cannot prove: **what Azure does at runtime** (DNS answers, HTTP status codes, effective NSG evaluation). Those need the live path below.

## The working template and three broken variants

| File | Omits exactly one control | Expected failure (live) |
|---|---|---|
| `main.bicep` | nothing; identical to the article | all checks pass |
| `variants/no-public-access-disable.bicep` | `publicNetworkAccess: 'Disabled'` | private path works, but the public endpoint stays reachable |
| `variants/no-dns-zone.bicep` | private DNS zone, VNet link and zone group | name resolves to a public IP; the error looks like a firewall problem |
| `variants/empty-nsg.bicep` | the two custom NSG rules | NSG is attached, but `AllowVNetInBound` (65000) still lets any VNet source in |

The full variant x check matrix is in [`verify/expected-results.md`](verify/expected-results.md). **Each cell is labelled `[offline]` (verified by `static-check.ps1`) or `[live]` (an expectation not yet run by the author).** Please do not read the live cells as measured results.

## Evidence you can regenerate

| What | Where | Regenerate with |
|---|---|---|
| Checklist for `main.bicep` (publicNetworkAccess, private endpoint, DNS zone and link, NSG rules) | [`evidence/checklist-main.txt`](evidence/checklist-main.txt) | `./verify/checklist.ps1` |
| Private baseline vs each broken case, control by control | [`evidence/exposed-vs-private.md`](evidence/exposed-vs-private.md) | `./scripts/generate-evidence.ps1` |
| Runner output for the broken cases | [`evidence/break-it-results.txt`](evidence/break-it-results.txt) | `./break-it/run-break-it.ps1` |
| DNS answers inside vs outside the VNet | [`evidence/dns-resolution-sample.md`](evidence/dns-resolution-sample.md) | **Sample, not measured**; record a real run with `scripts/run-live.ps1` |

## Now break it

[`break-it/`](break-it/) has one failing template per "false confidence" mistake (private endpoint with public access still on, missing DNS zone link, NSG only, wildcard NSG source, empty NSG). `./break-it/run-break-it.ps1` shows the checklist catching each one.

## Follow the build

Tags `step-1` to `step-4` match the article's four steps: [`step-1`](https://github.com/benceroth/lesson-bicep-private-storage/tree/step-1) address plan, [`step-2`](https://github.com/benceroth/lesson-bicep-private-storage/tree/step-2) app NSG, [`step-3`](https://github.com/benceroth/lesson-bicep-private-storage/tree/step-3) private storage, [`step-4`](https://github.com/benceroth/lesson-bicep-private-storage/tree/step-4) DNS and verification.

## Extend it

1. **Add a second private endpoint** for the `queue` subresource. Which DNS zone does it need, and what does the checklist need to learn to check it?
2. **Add a `checklist.ps1` control** that fails when `networkAcls.defaultAction` is not `Deny`, then add a `break-it/` case that trips it.
3. **Turn off Shared Key access** (`allowSharedKeyAccess: false`), then update `docs/limits.md` and the live checks to match.

## Verify it live (opt-in, costs money)

Billed: one private endpoint, three `Standard_B1s` VMs without public IPs, one storage account. Clean up afterwards.

```powershell
az login
./scripts/run-live.ps1 -ResourceGroup rg-harbor-verify -SshPublicKeyPath ~/.ssh/id_ed25519.pub -Variant main
./scripts/cleanup.ps1  -ResourceGroup rg-harbor-verify
```

It deploys the template, runs `verify/assert-config.ps1`, `verify/from-outside.ps1`, and `verify/from-inside.sh` on the VMs through `az vm run-command` (no Bastion). Blob access in the test uses a managed identity with *Storage Blob Data Reader*; no account keys. Repeat with `-Variant no-dns-zone` etc. to see each failure. Bash equivalents: `verify/*.sh`, `scripts/cleanup.sh`.

You can also run the article's own commands: `az deployment group what-if` then `create` with `main.bicep`. The `what-if` workflow is manual and opt-in.

## What it protects against (threat framing)

Prevented: anonymous or internet access to the storage data plane (public endpoint closed), and VNet-wide lateral access to the app subnet beyond the documented flow (integration to app on TCP 443).

Not prevented: a compromised identity or workload *inside* the allowed path, data exfiltration through allowed paths, a principal with excess RBAC, or use of account keys (the template leaves Shared Key access at its default). Details in [docs/limits.md](docs/limits.md).

## Layout

```
main.bicep, main.bicepparam   working template (same as the article)
bicepconfig.json              linter rules
variants/                     three broken templates, one omitted control each
break-it/                     five failing cases plus runner and README
evidence/                     committed, regenerable evidence (and one labelled DNS sample)
verify/                       checklist.ps1, static-check.ps1 (offline), assert-config, from-outside, from-inside, expected-results.md
test-vm/vm.bicep              optional VMs (no public IP; run-command)
scripts/                      run-live.ps1, generate-evidence.ps1, cleanup.ps1/.sh
policy/                       PSRule for Azure options, Checkov config
docs/                         flow-diagram (mermaid), dns-troubleshooting, address-plan, limits
.github/workflows/            validate (offline), what-if (opt-in)
```

## Known limits

- The author has not yet run the live checks; offline results are real, live results are expectations. See [`verify/expected-results.md`](verify/expected-results.md).
- `*.sh` scripts were written but not executed where this repo was authored; review before use.
- The Mermaid diagrams were not rendered locally (GitHub renders them).
- The baseline has no egress policy, no hybrid DNS, no logging, covers only the `blob` subresource, and does not disable Shared Key access. See [docs/limits.md](docs/limits.md).
- PSRule for Azure is run with documented exclusions (`policy/psrule-options.yaml`) because `main.bicep` must match the article.
- `variants/` are intentionally insecure. Never deploy them outside a throwaway resource group.

Tool versions: Bicep CLI 0.45.15, PSRule 2.9.0, PSRule.Rules.Azure 1.47.0, Checkov 3.2.x. Tags `step-1` to `step-4` mark the build steps; `v1.0.0` is not created yet.

## License

[MIT](LICENSE). See also [SECURITY.md](SECURITY.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

<sub>[Bence Roth](https://broth.hu/)</sub>
