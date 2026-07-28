# 03 - Exchange modern auth

Enable OAuth 2.0 on Exchange and register AD FS as the authorization server. This follows
Microsoft's guide, plus the fixes that guide omits.

Scripts: [../scripts/exchange/configure-modern-auth.ps1](../scripts/exchange/configure-modern-auth.ps1),
[../scripts/exchange/disable-extended-protection.ps1](../scripts/exchange/disable-extended-protection.ps1).

## 1. Register AD FS as the AuthServer

```powershell
New-AuthServer -Type ADFS -Name ADFS `
  -AuthMetadataUrl 'https://sts.corp.example/FederationMetadata/2007-06/FederationMetadata.xml'

# Without this the Bearer challenge omits authorization_uri and clients drift to Office 365:
Set-AuthServer -Identity ADFS -IsDefaultAuthorizationEndpoint $true

Set-OrganizationConfig -OAuth2ClientProfileEnabled $true
```

## 2. AD FS Application Group for Outlook

Register the well-known native Outlook client and a Web API per Exchange FQDN. See
[../scripts/adfs/add-application-group-outlook.ps1](../scripts/adfs/add-application-group-outlook.ps1).
Key points:

- Native client identifier: `d3590ed6-52b3-4102-aeff-aad2292ab01c` (Microsoft's Outlook app id).
- Redirect URIs include `ms-appx-web://Microsoft.AAD.BrokerPlugin/...`,
  `msauth.com.microsoft.Outlook://auth`, `urn:ietf:wg:oauth:2.0:oob`.
- A Web API for **each** Exchange namespace FQDN (`mail`, `autodiscover`).
- Issuance transform rules must emit `nameidentifier` (for the id_token subject) and the AD
  `primarysid` looked up by `DOMAIN\user`. Full rule set is in the script.
- When granting, `-ServerRoleIdentifier` must be a **string**, not the identifier collection.

## 3. Authentication policy

Block legacy per protocol, allow modern for the pilot users:

```powershell
New-AuthenticationPolicy 'Block Legacy Auth' `
  -BlockLegacyAuthActiveSync -BlockLegacyAuthImap -BlockLegacyAuthPop `
  -BlockLegacyAuthWebServices -BlockLegacyAuthRpc -BlockLegacyAuthAutodiscover -BlockLegacyAuthMapi -BlockLegacyAuthOfflineAddressBook

Set-OrganizationConfig -DefaultAuthenticationPolicy 'Block Legacy Auth'
# scope exceptions during migration:
# Set-User -Identity <user> -AuthenticationPolicy <policy>
```

## 4. Extended Protection MUST be relaxed behind an SSL-bridging proxy

Exchange CU14 enables Extended Protection (channel binding) by default. Behind an
SSL-bridging proxy the TLS channel binding token does not match, so OAuth calls fail with a
generic `[2605] server error`. Disable EP token checking on the virtual directories:

```powershell
Get-MapiVirtualDirectory        | Set-MapiVirtualDirectory        -ExtendedProtectionTokenChecking None
Get-WebServicesVirtualDirectory | Set-WebServicesVirtualDirectory -ExtendedProtectionTokenChecking None -Force
Get-OabVirtualDirectory         | Set-OabVirtualDirectory         -ExtendedProtectionTokenChecking None
Get-ActiveSyncVirtualDirectory  | Set-ActiveSyncVirtualDirectory  -ExtendedProtectionTokenChecking None
iisreset
```

> If your proxy does SSL pass-through (not bridging) you may keep EP - but then the WAF and
> host-based routing in [04](04-haproxy-ssl-bridging.md) are not possible.

## 5. Verify

- `Get-AuthServer ADFS | fl` - `IsDefaultAuthorizationEndpoint : True`.
- `Get-OrganizationConfig | fl OAuth2ClientProfileEnabled` - `True`.
- After a rich-client login, the EWS HttpProxy log
  (`...\Logging\HttpProxy\Ews\*.LOG`) shows `Bearer ... 200 ... ActAsUserVerified=True`.
