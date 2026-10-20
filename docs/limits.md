# Limits: what this baseline does not claim

Aligned with the article's "does and does not claim" section. The numbers and scenario are fictional (Harbor Ledger); the repo proves *configuration and behaviour of this sample*, not a production guarantee.

## What it claims (each is paired with a check)

| Claim | Check |
|---|---|
| Inbound to the app subnet is limited to TCP 443 from `10.40.1.0/24`; other VNet sources are denied | `static-check.ps1` (rules present), `assert-config` C8-C10, live TCP test |
| Storage public network access is disabled | `static-check.ps1`, `assert-config` C1, `from-outside` |
| A private endpoint to `blob` exists in `10.40.3.0/24` | `static-check.ps1`, `assert-config` C3 |
| The private DNS zone is linked and the endpoint registers its record | `static-check.ps1`, `assert-config` C4-C7, `from-inside` |

## What it does not claim

- **Not "zero trust in one file".** It is a set of inspectable claims.
- **No egress policy.** Default outbound is retained because the compute platform and its dependencies are not specified. Inventory DNS, identity, monitoring, update and application destinations before adding outbound denies.
- **Network controls are not authorization.** Private reachability grants no Blob permissions. The test VM uses Microsoft Entra authorization (managed identity with *Storage Blob Data Reader*); no account keys are used by any script.
- **Shared Key access is not disabled.** The template does not set `allowSharedKeyAccess`, so it keeps the Azure default (enabled). Anyone holding an account key could use it over the private path. Consider `allowSharedKeyAccess: false` and Entra-only access as a follow-up; it changes tooling that relies on keys, so evaluate it first.
- **Threats not addressed:** a compromised identity or workload *inside* the VNet that is allowed on the path, data exfiltration through allowed paths, a malicious insider with RBAC, and misuse of the storage data plane by authorized principals.
- **Hybrid and custom DNS:** no forwarding or DNS Private Resolver design; see [dns-troubleshooting.md](dns-troubleshooting.md).
- **Only the `blob` subresource.** `dfs`, `file`, `queue`, `table` and `web` need their own endpoints and zones.
- **No logging or monitoring.** For new traffic-flow logging, prefer Azure Virtual Network flow logs; NSG flow logs are on a retirement path.
- **Service tags are not fixed CIDR lists.** `VirtualNetwork` is a platform-maintained abstraction (it includes peered and connected ranges).
- **Static checks prove the template, not Azure.** `verify/static-check.ps1` reads compiled ARM JSON. Runtime behaviour is only verified live (`verify/expected-results.md`, section B), and the author has not run those cells.

## Scanner findings deliberately left in place

`main.bicep` must stay identical to the article, so these PSRule for Azure / Checkov findings are excluded in `policy/psrule-options.yaml` or reported advisory-only, not "fixed":

| Finding | Why it is left |
|---|---|
| `Azure.Resource.UseTags` | No tagging standard in the lesson. |
| `Azure.Storage.UseReplication` / CKV_AZURE_206 | `Standard_LRS` is a cost choice for the sample. |
| `Azure.Storage.SoftDelete`, `ContainerSoftDelete` | Data protection is out of scope. |
| `Azure.Storage.Firewall` / CKV_AZURE_35 | These check `networkAcls.defaultAction = Deny`; the template relies on `publicNetworkAccess = Disabled`. Adding `networkAcls.defaultAction: 'Deny'` is a reasonable defence-in-depth addition. |
| `Azure.Storage.LocalAuth` | See Shared Key above. |
| `Azure.VNET.UseNSGs` | The NSG is on `snet-app` only, matching the single documented flow. |
| `Azure.VNET.PrivateSubnet` | Default outbound retained (no egress design). |
| `Azure.NSG.LateralTraversal` | The deny rule is scoped to the app subnet. |
| CKV_AZURE_43 | Cannot evaluate the `uniqueString()` name expression. |

## Cost and cleanup (live path only)

The default path (build, lint, static check, PSRule) is offline and free. The live path bills for one private endpoint (hourly plus data processed), three `Standard_B1s` VMs with `Standard_LRS` disks, and the storage account. Costs depend on region and time left running, so no figure is given here. Always run `scripts/cleanup.ps1` (or `cleanup.sh`), then confirm with `az group exists`.
