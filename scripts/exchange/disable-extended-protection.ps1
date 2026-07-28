<#
.SYNOPSIS
    Relax Extended Protection on Exchange virtual directories behind an SSL-bridging proxy.
.DESCRIPTION
    Exchange CU14 enables Extended Protection (channel binding) by default. Behind a bridging
    proxy the channel binding token does not match, so OAuth calls fail with a generic
    [2605] server error. This sets ExtendedProtectionTokenChecking to None on the relevant
    virtual directories. Only run this if your proxy does SSL bridging (not pass-through).
.NOTES
    Run in the Exchange Management Shell as an Organization admin.
#>
$ErrorActionPreference = 'Stop'

Get-MapiVirtualDirectory        | Set-MapiVirtualDirectory        -ExtendedProtectionTokenChecking None
Get-WebServicesVirtualDirectory | Set-WebServicesVirtualDirectory -ExtendedProtectionTokenChecking None -Force
Get-OabVirtualDirectory         | Set-OabVirtualDirectory         -ExtendedProtectionTokenChecking None
Get-ActiveSyncVirtualDirectory  | Set-ActiveSyncVirtualDirectory  -ExtendedProtectionTokenChecking None

Write-Host "Extended Protection set to None on MAPI/EWS/OAB/EAS. Running iisreset..."
iisreset
