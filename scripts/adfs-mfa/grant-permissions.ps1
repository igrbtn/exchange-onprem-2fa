<#
.SYNOPSIS
    Delegate the two permissions the AD FS service account needs for the adfsmfa native TOTP
    adapter: write on the AD attributes that hold the TOTP secret, and Modify on the adfsmfa
    program/config directory (config.db).
.NOTES
    Run on the AD FS server / DC as a domain admin. Adjust the service account and domain DN.
    Without these the provider fails to initialize (config.db access denied) and enrollment
    cannot save the secret to AD.
#>
param(
    [string]$ServiceAccount = 'CORP\adfsgmsa$',   # the AD FS service (gMSA) account
    [string]$DomainDN       = 'DC=corp,DC=example',
    [string]$MfaPath        = 'C:\Program Files\MFA'
)
$ErrorActionPreference = 'Continue'

# a) Write access to the TOTP secret attributes (default adfsmfa ADDS template).
$attrs = 'msDS-cloudExtensionAttribute10','msDS-cloudExtensionAttribute11','msDS-cloudExtensionAttribute12',
         'msDS-cloudExtensionAttribute13','msDS-cloudExtensionAttribute14','msDS-cloudExtensionAttribute15',
         'msDS-cloudExtensionAttribute16','msDS-cloudExtensionAttribute17','msDS-cloudExtensionAttribute18','otherMailBox'
foreach ($a in $attrs) {
    dsacls $DomainDN /I:S /G ("${ServiceAccount}:RPWP;$a;user") | Out-Null
    Write-Host "delegated RPWP on $a"
}

# b) Modify on the adfsmfa dir so the AD FS service can read/write config.db.
icacls $MfaPath /grant ("${ServiceAccount}:(OI)(CI)M") /T /C | Select-Object -Last 1
Write-Host "granted Modify on $MfaPath to $ServiceAccount"
