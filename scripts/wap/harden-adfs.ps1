<#
.SYNOPSIS
    AD FS-side hardening for the WAP variant: Extranet Smart Lockout, disable the IdP-initiated
    sign-on page, and remove WS-Trust Windows-transport from the proxy (extranet).
.NOTES
    Run on the AD FS server as admin. Restarts the AD FS service at the end.
#>
$ErrorActionPreference = 'Continue'
Import-Module ADFS

# Extranet Smart Lockout. Behind WAP, AD FS reads the real client IP from the
# X-MS-Forwarded-Client-IP header WAP injects, so per-IP lockout works.
Set-AdfsProperties -EnableExtranetLockout $true `
    -ExtranetLockoutMode ADFSSmartLockoutEnforce `
    -ExtranetLockoutThreshold 20 `
    -ExtranetObservationWindow (New-TimeSpan -Minutes 30)
Write-Host "Extranet Smart Lockout: enforce, threshold 20, window 30m."

# Disable the IdP-initiated sign-on page (attack surface, not needed for this design).
Set-AdfsProperties -EnableIdpInitiatedSignonPage $false
Write-Host "IdP-initiated sign-on page: disabled."

# Remove WS-Trust Windows-transport endpoints from the proxy (extranet lockout bypass vector).
# -Proxy $false, NOT Disable-AdfsEndpoint (which would also kill intranet WIA / hybrid).
foreach ($p in '/adfs/services/trust/2005/windowstransport','/adfs/services/trust/13/windowstransport') {
    try { Set-AdfsEndpoint -TargetAddressPath $p -Proxy $false -ErrorAction Stop | Out-Null; Write-Host "proxy off: $p" }
    catch { Write-Warning "endpoint $p : $($_.Exception.Message)" }
}

Restart-Service adfssrv -Force
Start-Sleep 6
Write-Host ("adfssrv: {0}" -f (Get-Service adfssrv).Status)
