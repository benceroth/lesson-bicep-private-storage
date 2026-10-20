# Address plan

| Item | Range | Purpose |
|---|---|---|
| `vnet-harbor-prod` | `10.40.0.0/16` | The whole network. |
| `snet-integration` | `10.40.1.0/24` | Integration tier; the only approved caller of the app. |
| `snet-app` | `10.40.2.0/24` | App workload; protected by `nsg-harbor-app-prod`. |
| `snet-private-endpoints` | `10.40.3.0/24` | Private endpoints only (`privateEndpointNetworkPolicies: Disabled`, as in the article's template). |
| Unallocated | `10.40.4.0/22` and onward | Room for growth. |

## Decisions to make before deploying

- **Choose ranges before peering or connecting on-premises.** Bicep reproduces an address collision perfectly; it cannot make overlapping CIDRs routable. The template exposes only `location` for this reason.
- **Do not reuse `10.40.0.0/16`** if your own network already uses it. Edit it in a reviewed change, not at deploy time.
- Azure reserves five addresses in every subnet (the first four and the last), so a `/24` has 251 usable addresses. A private endpoint uses one.

## NSG priorities

| Priority | Rule | Notes |
|---|---|---|
| 100 | Allow TCP 443 from `10.40.1.0/24` to `10.40.2.0/24` | The one documented flow. |
| 4000 | Deny `VirtualNetwork` to `10.40.2.0/24` | Overrides the default below. Gaps leave room for more specific rules. |
| 65000 | `AllowVNetInBound` (Azure default) | Why an empty NSG does not isolate subnets: see `variants/empty-nsg.bicep`. |
| 65001 / 65500 | `AllowAzureLoadBalancerInBound` / `DenyAllInBound` | Azure defaults. |

NSGs are stateful, so no mirrored outbound rule is needed for the response traffic. Outbound is left at Azure's default; see [limits.md](limits.md).
