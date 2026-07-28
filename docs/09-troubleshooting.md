# 09 - Troubleshooting

Every error we hit building this, with the root cause and fix. These are the things the
official docs do not tell you.

## How to diagnose the OAuth flow

The single most useful signal is the **HAProxy access log**. When AD FS and Exchange event
logs stay silent, HAProxy shows the exact AD FS error in the redirect URL:
`/common/sso/final?...&error=server_error&error_description=MSIS...`.

The Exchange Bearer challenge only appears when you present a token:
```bash
curl -k -H "Authorization: Bearer x" https://mail.corp.example/mapi/emsmdb/
# look for WWW-Authenticate: Bearer authorization_uri=https://sts.corp.example/adfs/oauth2/authorize
```

The EWS/MAPI HttpProxy logs on Exchange (`...\Logging\HttpProxy\{Ews,Mapi}\*.LOG`) show
`Bearer`, HTTP status, and `ActAsUserVerified`.

---

## Errors and fixes

### 1. Outlook `[7q6ck]` "the operation attempted is invalid" (before AD FS opens)

The client is not a supported OS. Rich-client modern auth needs the **Windows 11 22H2+**
OS-level WAM broker. Windows Server 2022 (build 20348) and Windows 10 do not have it.
**Fix:** use a Windows 11 22H2+ client with KB5023706.

### 2. Client drifts to Office 365 / Bearer challenge has no `authorization_uri`

The AuthServer is not marked as the default authorization endpoint, so Exchange does not
advertise the on-prem `authorization_uri`.
**Fix:** `Set-AuthServer -Identity ADFS -IsDefaultAuthorizationEndpoint $true`.

### 3. ID4037 "the key needed to verify the signature could not be resolved" (SAML KC -> AD FS)

Keycloak puts its own key id (`KEY_ID`) in the SAML `KeyInfo`, which AD FS cannot map to the
trust's signing certificate.
**Fix:** on the Keycloak SAML client set
`saml.server.signature.keyinfo.xmlSigKeyInfoKeyNameTransformer = CERT_SUBJECT`, ensure the
Keycloak signing certificate is on the AD FS Claims Provider Trust, and
`Restart-Service adfssrv`.

### 4. Outlook `[2605]` "server error" after TOTP (token never reaches Exchange) - cause A

Extended Protection (channel binding) is enabled on the Exchange virtual directories (CU14
default) but the SSL-bridging proxy breaks the binding token.
**Fix:** `Set-*VirtualDirectory -ExtendedProtectionTokenChecking None` on MAPI/EWS/OAB/EAS,
then `iisreset`.

### 5. Outlook `[2605]` "server error" - cause B: MSIS9642

Found only in the HAProxy log as `...&error_description=MSIS9642: ... unable to construct an
id token ...`. The external Claims Provider Trust has no anchor claim, so AD FS cannot build
the id_token subject.
**Fix:** `Set-AdfsClaimsProviderTrust -TargetName <name> -AnchorClaimType
'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn'`.

### 6. POLICY0018 / POLICY3826 "not in domain\user format"

An AD attribute-store claim rule uses `query = ";objectSid;{0}"`, which expects `DOMAIN\user`,
but was fed a UPN.
**Fix:** transform the UPN first:
`param = RegExReplace(c.Value, "^(.*)@corp\.example$", "CORP\$1")`.

### 7. MSIS5004 "WSFederationPassiveEndpoint is not configured"

A Relying Party Trust has no WS-Fed passive endpoint. OWA and ECP each need their own.
**Fix:** `Add-/Set-AdfsRelyingPartyTrust ... -WSFedEndpoint <url>` (one RP trust per endpoint).

### 8. IIS 404 flashes in the Outlook popup after a successful login

After auth the MSAL/WAM broker navigates to `sts.corp.example/common/sso/final` - an
Azure-AD-ism AD FS does not implement, so IIS returns 404. The broker already read the auth
code from the URL, so login is fine; only the flash is ugly.
**Fix:** in HAProxy return a blank 200 for `/common/sso/*` on the AD FS host (see
[04-haproxy-ssl-bridging.md](04-haproxy-ssl-bridging.md)).

### 9. Keycloak login page is blank inside Outlook

The default `keycloak.v2` (React) theme does not render in the embedded WebView.
**Fix:** use a custom theme with `parent=keycloak` (classic server-rendered FTL). See
[08-keycloak-login-theme.md](08-keycloak-login-theme.md).

### 10. Custom Keycloak theme not applied / "layout is null"

Either the theme cache is serving the old theme, or `login.ftl` is missing its layout import.
**Fix:** start `login.ftl` with `<#import "template.ftl" as layout>`, and while developing add
`--spi-theme-cache-themes=false --spi-theme-cache-templates=false`.

### 11. Keycloak login "Invalid username or password" when logging in by UPN

The LDAP federation `usernameLDAPAttribute` is `cn` (or `sAMAccountName`), so Keycloak matches
the entered UPN against the wrong attribute.
**Fix:** set `usernameLDAPAttribute = userPrincipalName`, remove imported users, run a full
sync.

### 12. Keycloak realm sub-component silently orphaned / LDAP sync reports "0 imported"

When creating realm components via REST/kcadm, `parentId` was set to the realm **name**
instead of the realm **UUID**.
**Fix:** use the realm UUID (`GET /admin/realms/<realm>` -> `.id`) as `parentId`.

### 13. AD FS / Exchange backend answers HTTP 400 "Invalid Hostname" through HAProxy

The re-encrypt backend did not send SNI; http.sys refuses the request.
**Fix:** on the backend server line add `sni str(<fqdn>)` and `check-sni <fqdn>`.

### 14. Exchange setup: all prepare steps fail with exit code 1 (RebootPending)

Prereqs (VC++, URL Rewrite, UCMA) leave a pending-reboot flag, which `Setup /PrepareSchema`
refuses to run through.
**Fix:** reboot between installing prereqs and running `/PrepareSchema`.

### 15. Exchange setup: UCMA 4.0 will not install

`UcmaRuntime.exe /q` is a bootstrapper (a `-Wait` on it returns immediately); direct
`msiexec /i UcmaRuntime.msi` is blocked by a LaunchCondition.
**Fix:** install `SpeechPlatformRuntime.msi`, then run the bootstrapper
`Setup.exe /passive /norestart` and poll the Uninstall registry key until "Unified
Communications Managed API 4.0 ... Core Runtime" appears.

### 16. Exchange: "Database is mandatory on UserMailbox" during setup

Duplicate arbitration mailboxes accumulated in `CN=Users` from previous `PrepareAD` runs.
**Fix:** remove the stale system objects and run a fresh `PrepareAD`:
```powershell
Get-ADObject -LDAPFilter '(|(cn=SystemMailbox*)(cn=FederatedEmail*)(cn=Migration.*)(cn=DiscoverySearchMailbox*))' `
  -SearchBase 'DC=corp,DC=example' | Remove-ADObject -Recursive
```

### 17. Outlook New / Gmail / Outlook mobile never get the TOTP prompt

Those clients do not support on-prem AD FS modern auth and fall back to Basic auth.
**Fix:** use Outlook Classic (Windows), macOS Mail, or iOS Mail. Scope any Basic-auth
allowance narrowly and understand it bypasses the second factor.
