<#
.SYNOPSIS
    Prepare a Windows 11 client for Exchange on-prem modern auth (rich clients).
.DESCRIPTION
    Trusts the on-prem AD FS domain for the WAM broker and tells Office to prefer the on-prem
    endpoint instead of jumping to Office 365. Requires Windows 11 22H2+ (OS-level WAM broker)
    and Outlook M365 Apps / 2021 Retail 2304+.
.NOTES
    Run as the signed-in user (HKCU writes) with admin rights (HKLM writes). Adjust the STS FQDN.

    WARNING about -ExcludeO365Endpoint: it sets ExcludeExplicitO365Endpoint, which stops Office
    from ever contacting the Office 365 endpoint. Use it ONLY in a pure on-prem environment.
    In a hybrid / Exchange Online deployment it breaks Autodiscover and modern auth for the
    cloud mailboxes - leave it off ($false, the default) there.
#>
param(
    [string]$StsFqdn = 'sts.corp.example',

    # Force on-prem only. ONLY safe when there is NO Office 365 / Exchange Online in production.
    [switch]$ExcludeO365Endpoint
)

$ErrorActionPreference = 'Stop'

# HKLM: trust the on-prem AD FS domain (both forms - with and without trailing slash).
$trustPath = 'SOFTWARE\Policies\Microsoft\AAD\AuthTrustedDomains'
New-Item "HKLM:\$trustPath" -Force | Out-Null
$k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($trustPath, $true)
$k.CreateSubKey("https://$StsFqdn/") | Out-Null
$k.CreateSubKey("https://$StsFqdn")  | Out-Null

# HKCU: Office identity - enable on-prem modern auth.
$identity = 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Identity'
New-Item $identity -Force | Out-Null
Set-ItemProperty $identity -Name EnableExchangeOnPremModernAuth -Value 1 -Type DWord

# ExcludeExplicitO365Endpoint - ONLY for pure on-prem (no O365 in production). See the WARNING
# in .NOTES. In a hybrid / Exchange Online tenant this breaks cloud-mailbox Autodiscover.
if ($ExcludeO365Endpoint) {
    Set-ItemProperty $identity -Name ExcludeExplicitO365Endpoint -Value 1 -Type DWord
    $autod = 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Autodiscover'
    New-Item $autod -Force | Out-Null
    Set-ItemProperty $autod -Name ExcludeExplicitO365Endpoint -Value 1 -Type DWord
    Write-Host "ExcludeExplicitO365Endpoint set (on-prem only mode)."
} else {
    Write-Host "Skipped ExcludeExplicitO365Endpoint (safe for hybrid). Pass -ExcludeO365Endpoint for pure on-prem."
}

$exch = 'HKCU:\SOFTWARE\Microsoft\Exchange'
New-Item $exch -Force | Out-Null
Set-ItemProperty $exch -Name AlwaysUseMSOAuthForAutoDiscover -Value 1 -Type DWord

Write-Host "Client prepared. Fully close Outlook, then re-add the mailbox to trigger the"
Write-Host "AD FS -> Keycloak -> TOTP browser popup."
