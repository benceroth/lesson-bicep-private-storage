# DNS resolution: inside vs outside the VNet

> **Sample output, not a measured run.** It shows what `main.bicep` is expected to produce; it was written by hand from the Microsoft private endpoint DNS documentation. Replace it with a recorded run from `scripts/run-live.ps1` (see `verify/expected-results.md`). The account name and the public address are placeholders.

## Inside `vnet-harbor-prod` (zone linked)

```
$ nslookup stharborexample.blob.core.windows.net
Non-authoritative answer:
stharborexample.blob.core.windows.net  canonical name = stharborexample.privatelink.blob.core.windows.net.
Name:    stharborexample.privatelink.blob.core.windows.net
Address: 10.40.3.4
```

The answer is a private address from `10.40.3.0/24`. `verify/from-inside.sh` passes this step.

## Outside the VNet (public DNS)

```
$ nslookup stharborexample.blob.core.windows.net
Non-authoritative answer:
stharborexample.blob.core.windows.net  canonical name = stharborexample.privatelink.blob.core.windows.net.
...
Address: 203.0.113.10
```

Public DNS returns a public address (placeholder from the documentation range). With `publicNetworkAccess: Disabled`, a request to it is refused at the network layer. `verify/from-outside.ps1` checks that.

## Inside the VNet without the zone link (`break-it/02-missing-dns-zone-link.bicep`)

The same query inside the VNet returns the public address, because the VNet cannot see the private zone. The private endpoint is healthy, yet the application takes the public path and gets a firewall-looking error. See `docs/dns-troubleshooting.md`.
