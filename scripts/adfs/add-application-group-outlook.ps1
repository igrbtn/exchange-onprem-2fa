<#
.SYNOPSIS
    Create the AD FS Application Group for rich-client modern auth (Outlook / EWS / MAPI / EAS).
.DESCRIPTION
    Registers the well-known Outlook native client and one Web API per Exchange FQDN. Issuance
    rules emit nameidentifier (id_token subject), the AD primarysid by DOMAIN\user, the UPN,
    appidacr=2 and the scp scopes. Grants the native client access to the Web APIs.
.NOTES
    Run on the AD FS server as admin. Adjust FQDN / domain / NetBIOS parameters.
#>
param(
    [string[]]$ExchangeFqdns = @('mail.corp.example','autodiscover.corp.example'),
    [string]$AdDnsDomain     = 'corp.example',
    [string]$NetBios         = 'CORP'
)

$ErrorActionPreference = 'Stop'
$groupName   = 'Outlook'
$nativeId    = 'd3590ed6-52b3-4102-aeff-aad2292ab01c'   # Microsoft Outlook native client id
$redirects   = @(
    "ms-appx-web://Microsoft.AAD.BrokerPlugin/$nativeId",
    'msauth.com.microsoft.Outlook://auth',
    'urn:ietf:wg:oauth:2.0:oob'
)

if (-not (Get-AdfsApplicationGroup -Name $groupName -ErrorAction SilentlyContinue)) {
    New-AdfsApplicationGroup -Name $groupName -ApplicationGroupIdentifier $groupName
}

foreach ($scope in @('EAS.AccessAsUser.All','EWS.AccessAsUser.All','offline_access')) {
    if (-not (Get-AdfsScopeDescription -Name $scope -ErrorAction SilentlyContinue)) {
        Add-AdfsScopeDescription -Name $scope -Description $scope
    }
}

Add-AdfsNativeClientApplication -Name 'Outlook Native' -ApplicationGroupIdentifier $groupName `
    -Identifier $nativeId -RedirectUri $redirects

$issuance = @"
@RuleName = "NameID for id_token sub"
c:[Type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn"]
 => issue(Type = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier", Value = c.Value);

@RuleName = "PrimarySID from AD by UPN"
c:[Type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn"]
 => issue(store = "Active Directory",
    types = ("http://schemas.microsoft.com/ws/2008/06/identity/claims/primarysid"),
    query = ";objectSid;{0}",
    param = RegExReplace(c.Value, "^(.*)@$($AdDnsDomain -replace '\.','\.')`$", "$NetBios\`$1"));

@RuleName = "ActiveDirectoryUPN"
c:[Type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn"] => issue(claim = c);

@RuleName = "AppIDACR"     => issue(Type = "appidacr", Value = "2");
@RuleName = "SCP"          => issue(Type = "scp", Value = "user_impersonation");
@RuleName = "SCPEAS"       => issue(Type = "scp", Value = "EAS.AccessAsUser.All");
@RuleName = "SCPEWS"       => issue(Type = "scp", Value = "EWS.AccessAsUser.All");
@RuleName = "offlineaccess"=> issue(Type = "scp", Value = "offline_access");
"@

foreach ($fqdn in $ExchangeFqdns) {
    $apiId = "https://$fqdn/"
    Add-AdfsWebApiApplication -Name "Exchange Web API $fqdn" -ApplicationGroupIdentifier $groupName `
        -Identifier $apiId -IssuanceTransformRules $issuance `
        -AccessControlPolicyName 'Permit everyone'
}

$scopes = @('openid','profile','email','user_impersonation','offline_access','EAS.AccessAsUser.All','EWS.AccessAsUser.All')
Get-AdfsWebApiApplication -ApplicationGroupIdentifier $groupName | ForEach-Object {
    # ServerRoleIdentifier must be a STRING, not the identifier collection.
    $server = [string]($_.Identifier | Select-Object -First 1)
    Grant-AdfsApplicationPermission -ClientRoleIdentifier $nativeId -ServerRoleIdentifier $server -ScopeNames $scopes
}

Write-Host "Application Group '$groupName' created for: $($ExchangeFqdns -join ', ')"
