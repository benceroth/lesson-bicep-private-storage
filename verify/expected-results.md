# Expected results: variant x check

This table is the heart of the repo: every control is necessary, and removing any one of them breaks something the others do not catch.

**How to read it.** Every cell says *how* it is verified:

- **[offline]** is asserted by `verify/static-check.ps1` on the compiled ARM JSON. This was run (see "What has actually been run" below). It proves the *template declares* the control. It does not prove Azure behaves accordingly.
- **[live]** is an *expectation* derived from Microsoft documentation and the template. It has **not been run by the author** at the time of writing; it needs a deployment (`scripts/run-live.ps1`). Treat it as a hypothesis until you, or a recorded run added to this file, confirm it.

Legend: PASS = the control works / the check passes. FAIL = the check fails, which is the documented failure of that variant.

## A. Template declares the control [offline]

| Control (static-check id) | `main.bicep` | `no-public-access-disable` | `no-dns-zone` | `empty-nsg` |
|---|---|---|---|---|
| `PublicAccessDisabled` (storage `publicNetworkAccess = Disabled`) | present | **ABSENT** | present | present |
| `BlobPublicAccessOff` (`allowBlobPublicAccess = false`) | present | present | present | present |
| `PrivateEndpointBlob` (PE with group `blob`) | present | present | present | present |
| `DnsZone` (`privatelink.blob.*`) | present | present | **ABSENT** | present |
| `DnsVnetLink` (zone linked to the VNet) | present | present | **ABSENT** | present |
| `DnsZoneGroup` (zone group on the PE) | present | present | **ABSENT** | present |
| `NsgAllowIntegration443` (priority 100) | present | present | present | **ABSENT** |
| `NsgDenyOtherVnet` (priority 4000) | present | present | present | **ABSENT** |
| `NsgAttachedToApp` (NSG on `snet-app`) | present | present | present | present |

Note `empty-nsg` still *attaches* an NSG: attached is not the same as effective.

## B. Runtime behaviour [live - NOT run by the author]

| Check | Script | `main.bicep` | `no-public-access-disable` | `no-dns-zone` | `empty-nsg` |
|---|---|---|---|---|---|
| Inside VNet: blob hostname resolves to `10.40.3.x` | `from-inside.sh` | PASS | PASS | **FAIL** (resolves to a public address: no private zone) | PASS |
| Inside VNet: blob list over the private path with managed identity | `from-inside.sh` | PASS (HTTP 200) | PASS (HTTP 200) | **FAIL** (request goes to the public endpoint and is refused by the firewall; reads like a firewall problem, is a DNS problem) | PASS (HTTP 200) |
| Outside VNet: anonymous request refused at the network layer (403 `AuthorizationFailure`) | `from-outside.ps1/.sh` | PASS | **FAIL** (request reaches storage authorization; a different error than `AuthorizationFailure` is expected) | PASS | PASS |
| `integration` subnet to app subnet TCP 443 allowed | `from-inside.sh` (3rd/4th args) | PASS | PASS | PASS | PASS (also allowed by the default rule) |
| Other subnet in the VNet to app subnet TCP 443 denied | `from-inside.sh ... deny nsg-only` | PASS | PASS | PASS | **FAIL** (`AllowVNetInBound`, priority 65000, still permits it) |
| Configuration checks C1-C10 | `assert-config.ps1/.sh` | all PASS | C1 fails | C4-C7 fail | C8, C9 fail |

Two precise statements worth testing, because they are easy to get wrong:

1. In `no-dns-zone`, the private endpoint and its private IP *exist*; `assert-config` C3 passes. Only the name resolution is wrong. Nothing in the portal marks the endpoint "unhealthy".
2. In `no-public-access-disable`, the private path works perfectly. A happy-path test passes; only the *negative* test (`from-outside`) catches it.

The exact HTTP status and error code strings in section B are what the author expects; confirm them on a real deployment and update this file with the observed values (and the date, region and Bicep version).

## What has actually been run

| Item | Status |
|---|---|
| `az bicep build` and `az bicep lint` on `main.bicep`, every variant and `test-vm/vm.bicep` | run, clean (Bicep CLI 0.45.15) |
| `verify/static-check.ps1` (section A) | run, passes |
| PSRule for Azure 1.47.0 on `main.bicep` with `policy/psrule-options.yaml` | run, passes (27 rules; documented exclusions) |
| Checkov 3.2.533 on `main.bicep` | run, 9 passed / 3 failed, advisory (see `policy/checkov.yaml`) |
| Section B and `assert-config` against a deployed resource group | **not run** (no Azure subscription was available) |
| `*.sh` scripts | **not executed** (no bash available where this repo was authored); review before relying on them |
| `scripts/run-live.ps1`, `test-vm/vm.bicep` deployment | **not deployed**; the template compiles and lints only |

## Recording a live run

When you run it live, paste results here as a dated block, for example:

```
Run date: YYYY-MM-DD   Region: westeurope   Bicep: x.y.z   Variant: main
C1 PASS ... (output of assert-config)
```

Do not include subscription IDs, tenant IDs or storage account names you want to keep private.
