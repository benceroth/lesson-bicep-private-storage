# Flow diagram

Source for the article's "building with controlled doors" figure. Render with any Mermaid renderer (GitHub renders it inline).

## Data and policy path

```mermaid
flowchart LR
  internet([Internet])
  subgraph vnet["vnet-harbor-prod 10.40.0.0/16"]
    direction LR
    integ["snet-integration<br/>10.40.1.0/24"]
    subgraph appsub["snet-app 10.40.2.0/24"]
      nsg{{"NSG nsg-harbor-app-prod<br/>100 Allow 10.40.1.0/24 to 443<br/>4000 Deny VirtualNetwork<br/>65000 AllowVNetInBound (default)"}}
      app["App workload"]
    end
    pe["snet-private-endpoints 10.40.3.0/24<br/>pe-harbor-blob-prod (10.40.3.x)"]
    other["any other VNet source"]
  end
  storage[("Storage account<br/>publicNetworkAccess = Disabled")]

  integ -- "TCP 443 (allowed, priority 100)" --> nsg --> app
  other -. "denied by priority 4000" .-> nsg
  app -- "Blob over Private Link" --> pe --> storage
  internet -. "public endpoint closed: 403 AuthorizationFailure" .-> storage
```

## DNS path (the part that is easy to forget)

```mermaid
sequenceDiagram
  participant App as App (in VNet)
  participant AzDNS as Azure DNS (168.63.129.16)
  participant Zone as Private DNS zone privatelink.blob.core.windows.net
  participant PE as Private endpoint 10.40.3.x
  App->>AzDNS: stharbor....blob.core.windows.net ?
  AzDNS->>AzDNS: CNAME to stharbor....privatelink.blob.core.windows.net
  AzDNS->>Zone: zone linked to the VNet? (virtualNetworkLink)
  Zone-->>AzDNS: A record 10.40.3.x (created by the DNS zone group)
  AzDNS-->>App: 10.40.3.x
  App->>PE: TCP 443 (private path)
```

If the zone, the VNet link or the zone group is missing (`variants/no-dns-zone.bicep`), the chain ends at the public IP and the private endpoint is never used. See [dns-troubleshooting.md](dns-troubleshooting.md).

## Which control closes which door

| Door | Control | Variant that leaves it open |
|---|---|---|
| App subnet reachable from any VNet source | NSG priority 4000 deny | `empty-nsg` |
| Storage public endpoint | `publicNetworkAccess: 'Disabled'` | `no-public-access-disable` |
| Clients pointed at the wrong address | Private DNS zone + link + zone group | `no-dns-zone` |
