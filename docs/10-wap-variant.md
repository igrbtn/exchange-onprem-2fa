# 10 - Variant: AD FS Web Application Proxy (WAP) instead of HAProxy

This is an alternative to the HAProxy front end ([04](04-haproxy-ssl-bridging.md)). WAP is
Microsoft's own reverse proxy for AD FS and published web apps. Everything else in this guide
(AD FS, Keycloak, Exchange modern auth, the client registry) is identical - only the box in
front of the backends changes.

## HAProxy vs WAP - which to pick

| | HAProxy | WAP |
| --- | --- | --- |
| Platform | Linux | Windows Server role |
| AD FS proxy | manual re-encrypt | native, supported |
| App-layer WAF (Coraza) | yes | no |
| Security headers / rate limiting | yes | no (Schannel/AD FS hardening only) |
| Pre-authentication | no | optional (AD FS pre-auth) |

If you need the WAF and header/rate-limit hardening, keep HAProxy - or put HAProxy **in front
of** WAP as a hybrid (client -> HAProxy(WAF) -> WAP -> AD FS/Exchange). This doc covers the
pure WAP replacement.

## Topology

A dedicated Windows Server (2019+) in the perimeter:

```
Client --443--> WAP (proxies /adfs/*, pass-through publishes Exchange/Keycloak)
    sts.corp.example        -> AD FS       (10.0.0.10)
    kc.corp.example         -> Keycloak    (10.0.0.10:8080)
    mail/autodiscover...    -> Exchange    (10.0.0.20)
```

> **Keep WAP workgroup (NOT domain-joined).** It sits in the DMZ; if compromised it must not
> already be inside the domain. Trust to AD FS is established once, over the network, with a
> domain-admin credential passed to `Install-WebApplicationProxy` - the box stays workgroup.

## Prerequisites

- A Windows Server (2019+) VM, workgroup, reachable on 443 by clients and able to reach the
  AD FS / Keycloak / Exchange backends.
- **Trust the internal root CA** on the WAP box (`Import-Certificate ... Cert:\LocalMachine\Root`).
- A **multi-SAN certificate with private key** (PFX) covering `sts`, `mail`, `autodiscover`,
  `kc` (the same cert HAProxy used). Import it into `Cert:\LocalMachine\My`.
- **Split-brain host resolution on WAP**: WAP must resolve the published FQDNs to the *real
  backends* (external clients resolve them to WAP). Add to the WAP hosts file:
  ```
  10.0.0.10 sts.corp.example
  10.0.0.10 kc.corp.example
  10.0.0.20 mail.corp.example
  10.0.0.20 autodiscover.corp.example
  ```

Script: [../scripts/wap/import-certs.ps1](../scripts/wap/import-certs.ps1).

## 1. Install the WAP role and establish trust

```powershell
Install-WindowsFeature Web-Application-Proxy -IncludeManagementTools

$cred = Get-Credential   # a domain admin, used ONCE to establish the proxy trust
Install-WebApplicationProxy `
  -FederationServiceName 'sts.corp.example' `
  -CertificateThumbprint '<MULTISAN_THUMBPRINT>' `
  -FederationServiceTrustCredential $cred
```

Script: [../scripts/wap/install-wap.ps1](../scripts/wap/install-wap.ps1).

> **Gotcha - "Could not establish trust relationship for the SSL/TLS secure channel".**
> AD FS often presents a **self-signed** SSL certificate (subject == issuer). A reverse proxy
> that validates strictly (WAP does) rejects it as `UntrustedRoot`; an SSL-bridging proxy like
> HAProxy hides this because it uses `verify none`. Two fixes:
> - **Production:** give AD FS a **CA-issued** SSL certificate so any proxy trusts it.
> - **Lab quick fix:** import the AD FS self-signed cert into the WAP `LocalMachine\Root`.
>
> Also watch enterprise-CA CRL distribution points published only in **LDAP** - a workgroup
> WAP cannot reach them, and the revocation-check failure surfaces as the same SSL trust error.

## 2. Publish the applications (pass-through)

Keycloak is **not** an AD FS relying party (AD FS delegates *to* it), so it and the Exchange
endpoints are published **pass-through** (no AD FS pre-auth - rich-client OAuth needs it).
`/adfs/*` is proxied natively by the federation role; no app entry is needed for it.

```powershell
$thumb = '<MULTISAN_THUMBPRINT>'
Add-WebApplicationProxyApplication -Name 'Exchange'     -ExternalPreauthentication PassThrough -ExternalUrl 'https://mail.corp.example/'         -BackendServerUrl 'https://mail.corp.example/'         -ExternalCertificateThumbprint $thumb
Add-WebApplicationProxyApplication -Name 'Autodiscover' -ExternalPreauthentication PassThrough -ExternalUrl 'https://autodiscover.corp.example/' -BackendServerUrl 'https://autodiscover.corp.example/' -ExternalCertificateThumbprint $thumb
Add-WebApplicationProxyApplication -Name 'Keycloak'     -ExternalPreauthentication PassThrough -ExternalUrl 'https://kc.corp.example/'           -BackendServerUrl 'http://kc.corp.example:8080/'       -ExternalCertificateThumbprint $thumb
```

Script: [../scripts/wap/publish-apps.ps1](../scripts/wap/publish-apps.ps1).

## 3. Repoint clients

Point the client-facing DNS (`mail`, `autodiscover`, `sts`, `kc`) at the WAP IP. Everything
downstream (OWA -> AD FS -> Keycloak -> TOTP; Outlook OAuth) is unchanged.

## Hardening

WAP has no WAF or header/rate-limit surface, so harden at the TLS and AD FS layers.

### TLS / Schannel (on the WAP box)

Disable legacy protocols and weak ciphers; force TLS 1.2 (+ 1.3 on WS2022). Registry under
`HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL`: disable SSL 2.0/3.0,
TLS 1.0/1.1 (Enabled=0, DisabledByDefault=1), enable TLS 1.2, disable RC4/DES/3DES/NULL
ciphers, and set `SchUseStrongCrypto`/`SystemDefaultTlsVersions` on .NET 4 so the WAP service
talks TLS 1.2 to AD FS. **Requires a reboot.** All lab clients (Win11, macOS, iOS) and all
backends (WS2022, Keycloak/JDK21) support TLS 1.2, so nothing breaks.

Script: [../scripts/wap/harden-wap-schannel.ps1](../scripts/wap/harden-wap-schannel.ps1).

### AD FS (on the AD FS server)

- **Extranet Smart Lockout (ESL)** - per-IP lockout of password guessing. Behind WAP, AD FS
  reads the real client IP from the `X-MS-Forwarded-Client-IP` header WAP injects, so ESL works:
  ```powershell
  Set-AdfsProperties -EnableExtranetLockout $true -ExtranetLockoutMode ADFSSmartLockoutEnforce `
    -ExtranetLockoutThreshold 20 -ExtranetObservationWindow (New-TimeSpan -Minutes 30)
  ```
- **Disable the IdP-initiated sign-on page** (attack surface, not needed):
  `Set-AdfsProperties -EnableIdpInitiatedSignonPage $false`.
- **Remove WS-Trust Windows-transport from the proxy** (extranet lockout bypass vector). Use
  `-Proxy $false`, NOT `Disable-AdfsEndpoint` (which would also kill intranet WIA / hybrid):
  ```powershell
  Set-AdfsEndpoint -TargetAddressPath '/adfs/services/trust/2005/windowstransport' -Proxy $false
  Set-AdfsEndpoint -TargetAddressPath '/adfs/services/trust/13/windowstransport'   -Proxy $false
  ```

Script: [../scripts/wap/harden-adfs.ps1](../scripts/wap/harden-adfs.ps1).

## Caveats vs the HAProxy build

- **OWA in a browser hangs on "Starting..." through WAP.** WAP pass-through does not upgrade
  OWA's notification **WebSocket**; OWA repeatedly waits out the timeout, so the shell loads but
  the mailbox never renders (resources trickle in minutes apart). Rich clients (Outlook, EAS) and
  AD FS/Keycloak sign-in are unaffected - only browser OWA. **Fix: front the browser path with
  HAProxy** (the hybrid below), which handles the WebSocket (`timeout tunnel`).
- **No `/common/sso/*` 200 rule** - the post-auth 404 flash in the Outlook popup
  ([09 #7](09-troubleshooting.md)) can reappear. WAP has no easy synthetic-response hook.
- **No WAF / security headers / rate limiting.** If you need those, use the hybrid
  (HAProxy in front of WAP) or the pure HAProxy build.

Because of the OWA WebSocket limitation, a **hybrid** is often the best WAP deployment: HAProxy
(with the WAF and WebSocket handling) terminates client TLS and forwards to WAP, which remains the
supported AD FS proxy. Clients -> HAProxy -> WAP -> AD FS/Exchange.

## Verify

From a client repointed at WAP:

- `https://mail.corp.example/owa/` and `/ecp/` -> **302** to `sts.corp.example/adfs/ls` -> Keycloak -> TOTP.
- `https://sts.corp.example/FederationMetadata/2007-06/FederationMetadata.xml` -> **200**.
- `https://kc.corp.example/realms/<realm>/.well-known/openid-configuration` -> **200**.
- `https://mail.corp.example/mapi/emsmdb/` with a dummy Bearer -> **401** Bearer challenge.
- Interactive: OWA login (TOTP) and Outlook add-account both succeed through WAP.
