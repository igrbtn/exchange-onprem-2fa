<#
.SYNOPSIS
    Prepare a Windows 11 client for Exchange on-prem modern auth (rich clients).
.DESCRIPTION
    Trusts the on-prem AD FS domain for the WAM broker and tells Office to prefer the on-prem
    endpoint instead of jumping to Office 365. Requires Windows 11 22H2+ (OS-level WAM broker)
    and Outlook M365 Apps / 2021 Retail 2304+.
.NOTES
    Run as the signed-in user (HKCU writes) with admin rights (HKLM writes). Adjust the STS FQDN.
#>
param(
    [string]$StsFqdn = 'sts.corp.example'
)

$ErrorActionPreference = 'Stop'

# HKLM: trust the on-prem AD FS domain (both forms - with and without trailing slash).
$trustPath = 'SOFTWARE\Policies\Microsoft\AAD\AuthTrustedDomains'
New-Item "HKLM:\$trustPath" -Force | Out-Null
$k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($trustPath, $true)
$k.CreateSubKey("https://$StsFqdn/") | Out-Null
$k.CreateSubKey("https://$StsFqdn")  | Out-Null

# HKCU: Office identity - prefer on-prem, do not drift to O365.
$identity = 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Identity'
New-Item $identity -Force | Out-Null
Set-ItemProperty $identity -Name EnableExchangeOnPremModernAuth -Value 1 -Type DWord
Set-ItemProperty $identity -Name ExcludeExplicitO365Endpoint     -Value 1 -Type DWord

$autod = 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Autodiscover'
New-Item $autod -Force | Out-Null
Set-ItemProperty $autod -Name ExcludeExplicitO365Endpoint -Value 1 -Type DWord

$exch = 'HKCU:\SOFTWARE\Microsoft\Exchange'
New-Item $exch -Force | Out-Null
Set-ItemProperty $exch -Name AlwaysUseMSOAuthForAutoDiscover -Value 1 -Type DWord

Write-Host "Client prepared. Fully close Outlook, then re-add the mailbox to trigger the"
Write-Host "AD FS -> Keycloak -> TOTP browser popup."
