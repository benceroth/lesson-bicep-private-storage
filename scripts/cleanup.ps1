<#
.SYNOPSIS  Deletes the resource group created for the live checks (and everything in it).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $ResourceGroup,
  [switch] $Yes
)
if (-not $Yes) {
  $a = Read-Host "Delete resource group '$ResourceGroup' and everything in it? (type the name to confirm)"
  if ($a -ne $ResourceGroup) { Write-Host 'Aborted.'; exit 1 }
}
az group delete -n $ResourceGroup --yes --no-wait --only-show-errors
Write-Host "Deletion of '$ResourceGroup' started (asynchronous). Check: az group exists -n $ResourceGroup"
