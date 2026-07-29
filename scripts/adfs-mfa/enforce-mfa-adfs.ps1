<#
.SYNOPSIS
    AD FS-side configuration for the native TOTP variant: local password auth + require MFA.
.DESCRIPTION
    These are standard AD FS cmdlets (remotable). The require-MFA Access Control Policy is what
    actually triggers the MFA adapter in AD FS 2019 - the legacy additional-authentication rule
    alone frequently does not fire.
.NOTES
    Run on the AD FS server as admin.
#>
$ErrorActionPreference = 'Continue'

# Password check done locally by AD FS (not delegated to an external IdP).
Set-AdfsProperties -IntranetUseLocalClaimsProvider $true
Set-AdfsProperties -EnableLocalAuthenticationTypes $true

# Ensure the adfsmfa provider is in the global additional-auth providers.
$prov = @((Get-AdfsGlobalAuthenticationPolicy).AdditionalAuthenticationProvider)
if ($prov -notcontains 'MultiFactorAuthenticationProvider') {
    Set-AdfsGlobalAuthenticationPolicy -AdditionalAuthenticationProvider ($prov + 'MultiFactorAuthenticationProvider') -Force
}

foreach ($rp in (Get-AdfsRelyingPartyTrust | Where-Object { $_.Name -like 'Exchange*' })) {
    # No home-realm-discovery: use the local AD claims provider.
    Set-AdfsRelyingPartyTrust -TargetName $rp.Name -ClaimsProviderName @('Active Directory')
    # THE mechanism that forces MFA in AD FS 2019.
    Set-AdfsRelyingPartyTrust -TargetName $rp.Name -AccessControlPolicyName 'Permit everyone and require MFA'
    Write-Host "enforced MFA on RP: $($rp.Name)"
}

Restart-Service adfssrv -Force
Start-Sleep 6
Write-Host ("adfssrv: {0}" -f (Get-Service adfssrv).Status)
