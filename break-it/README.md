# break-it

One small, deliberately wrong template per "false confidence" mistake from the article. Each differs from `main.bicep` in one way, looks plausible in a review, and is caught by the offline checklist.

```powershell
./break-it/run-break-it.ps1                                  # all cases: expects CAUGHT for each
./verify/checklist.ps1 -Template break-it/02-missing-dns-zone-link.bicep   # one case, with the failing control
```

| Case | The mistake | Expected finding | Fix |
|---|---|---|---|
| `01-private-endpoint-public-access-on` | Private endpoint exists, `publicNetworkAccess` not disabled | `PublicAccessDisabled` | Set `publicNetworkAccess: 'Disabled'` on the storage account |
| `02-missing-dns-zone-link` | DNS zone and zone group exist, but the zone is not linked to the VNet | `DnsVnetLink` | Add the `virtualNetworkLinks` resource to `vnet-harbor-prod` |
| `03-nsg-only` | NSG rules are right, but no private endpoint, no private DNS, storage left public | `PublicAccessDisabled`, `PrivateEndpointBlob`, `DnsZone`, `DnsVnetLink`, `DnsZoneGroup` | Add the private endpoint, DNS zone, link and zone group, and disable public access |
| `04-wildcard-nsg-source` | Allow rule uses `sourceAddressPrefix: '*'` for convenience | `NsgAllowIntegration443` | Name the source: `10.40.1.0/24` |
| `05-empty-nsg` | An NSG is attached, but only Azure's default rules apply (`AllowVNetInBound` at 65000) | `NsgAllowIntegration443`, `NsgDenyOtherVnet` | Add the priority 100 allow and priority 4000 deny rules |

The runner prints `CAUGHT` only when the findings match the table exactly, so a checker that stops noticing a mistake fails the run.

These cases show what the **template declares**. Runtime behaviour (DNS answers, HTTP status codes) needs the live path in the main README. Never deploy these outside a throwaway resource group.
