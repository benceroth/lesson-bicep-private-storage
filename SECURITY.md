# Security Policy

## No secrets, no real identifiers

This repository must never contain credentials, storage account keys, SAS tokens, connection strings, SSH private keys, tenant IDs or real subscription IDs. The scripts authenticate to Blob Storage with a VM managed identity and Microsoft Entra authorization; none reads or prints account keys. The test VM accepts an SSH *public* key only and disables password sign-in.

The storage account name comes from `uniqueString(resourceGroup().id)`. Do not paste your real account name, subscription ID or tenant ID into issues, pull requests or `verify/expected-results.md`.

The optional `what-if.yml` workflow uses OIDC federated credentials (no client secret). The identifiers it needs are repository secrets, never committed files.

## Reporting a vulnerability or an accidental leak

Open a private security advisory (**Security -> Report a vulnerability**). Do not file a public issue for a suspected leak. If you find a real identifier or secret, report it and rotate it; history cleanup alone is not enough.

## Scope

This is a teaching sample for a fictional company. It demonstrates one private storage path and its verification, not a complete production baseline. See `docs/limits.md` for what it does not claim (no egress policy, Shared Key access not disabled, no hybrid DNS, no logging). The `variants/` templates are intentionally insecure: never deploy them to a real environment.
