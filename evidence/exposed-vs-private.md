| Control | Private baseline | NSG only | Endpoint, public on | No DNS link | Wildcard source | Empty NSG |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| storage publicNetworkAccess = Disabled | yes | **NO** | **NO** | yes | yes | yes |
| storage allowBlobPublicAccess = false | yes | yes | yes | yes | yes | yes |
| private endpoint targets the blob subresource | yes | **NO** | yes | yes | yes | yes |
| private DNS zone privatelink.blob.* declared | yes | **NO** | yes | yes | yes | yes |
| private DNS zone linked to the VNet | yes | **NO** | yes | **NO** | yes | yes |
| private endpoint has a DNS zone group | yes | **NO** | yes | yes | yes | yes |
| NSG allow 100: 10.40.1.0/24 -> 10.40.2.0/24 TCP 443 | yes | yes | yes | yes | **NO** | **NO** |
| NSG deny 4000: VirtualNetwork -> 10.40.2.0/24 | yes | yes | yes | yes | yes | **NO** |
| NSG attached to snet-app | yes | yes | yes | yes | yes | yes |
