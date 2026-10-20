# Contributing

Small and welcome: typo fixes, clearer docs, and **recorded live results** for `verify/expected-results.md`.

## Rules

1. `main.bicep` mirrors the article. Do not change it without also changing the article; open an issue first.
2. Each file in `variants/` omits exactly one control. If you edit one, update `verify/static-check.ps1` (expected control set) and `verify/expected-results.md`.
3. Never claim a live result you did not observe. Label cells **[offline]** or **[live]**.
4. No secrets, keys, subscription or tenant IDs, or real account names anywhere.

## Before opening a pull request

```powershell
az bicep install --version v0.45.15
az bicep build --file main.bicep
az bicep lint --file main.bicep          # also each file in variants/ and test-vm/
./verify/static-check.ps1
```

CI runs these plus PSRule for Azure (see `.github/workflows/validate.yml`).

## Live results

Live testing costs money and must be cleaned up (`scripts/cleanup.ps1`). If you contribute results, include date, region, Bicep version and variant, and remove all identifiers.
