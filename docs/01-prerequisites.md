# 01 - Prerequisites

## Hard requirements

| Component | Minimum | Notes |
| --- | --- | --- |
| Exchange Server | 2019 **CU13+** | Modern auth (OAuth) for on-prem shipped in CU13. CU14 tested. |
| AD FS | Windows Server 2019+ | Must NOT be co-located on the Exchange server. |
| Keycloak | 26.x | JDK 21. LDAP federation to AD. |
| HAProxy | 2.2+ | SPOE needed for the Coraza WAF integration. |
| Windows client (rich) | **Windows 11 22H2+** (build 22621+) | OS-level WAM broker is required. Windows Server 2022 / Windows 10 do NOT work for rich-client modern auth. Install KB5023706. |
| Outlook (rich) | M365 Apps or Outlook 2021 Retail **2304+** (16.0.17628+) | Outlook 2016/2019 not supported for on-prem modern auth. |

## Supported clients

Modern-auth rich clients that work end-to-end:

- Outlook **Classic** for Windows (Win11 22H2+)
- macOS Mail
- iOS Mail

Clients that silently fall back to Basic auth (i.e. do NOT get the TOTP prompt):

- Outlook **New** for Windows
- Outlook mobile (iOS/Android)
- Gmail app

Plan your rollout around the supported set, or keep a Basic-auth allow-policy scoped to the
unsupported clients during migration (and know that those bypass the second factor).

## Protocol coverage

| Protocol | Modern auth |
| --- | --- |
| MAPI/HTTP | Yes |
| EWS | Yes |
| Exchange ActiveSync (EAS) | Yes |
| Offline Address Book (OAB) | Yes |
| Autodiscover | Yes |
| RPC/HTTP (Outlook Anywhere) | No |
| IMAP4 / POP3 | No |

## Certificates and DNS

You need an internal CA (an AD CS Enterprise Root CA is fine) and three things: a multi-SAN
cert on HAProxy, a cert on Exchange, and DNS pointing clients at HAProxy.

### DNS

All client-facing names resolve to the HAProxy IP (clients never talk to the backends
directly). Point the backend server names at their real hosts for HAProxy's own re-encrypt
connections.

| Record | Resolves to | Used by |
| --- | --- | --- |
| `mail.corp.example` | HAProxy | OWA, ECP, MAPI, EWS, EAS, OAB |
| `autodiscover.corp.example` | HAProxy | Autodiscover |
| `owa.corp.example`, `ecp.corp.example` | HAProxy | optional split names (usually just use `mail`) |
| `sts.corp.example` | HAProxy | AD FS |
| `kc.corp.example` | HAProxy | Keycloak |

Also set the internal Autodiscover SCP and the Exchange virtual-directory URLs to
`https://mail.corp.example/...` so clients converge on the one namespace.

### HAProxy certificate (multi-SAN)

One certificate with SAN covering every client-facing name:
`mail`, `autodiscover`, `sts`, `kc` (and `owa`/`ecp` if you split them). Issue it from your CA,
export to PFX, then build the PEM HAProxy wants:

```bash
openssl pkcs12 -in haproxy.pfx -nodes -out /etc/haproxy/certs/lab.pem
chmod 600 /etc/haproxy/certs/lab.pem
```

### Exchange certificate

A separate server-auth cert (SAN `mail`, `autodiscover`, and the server FQDN). From the
Exchange Management Shell:

```powershell
$req = New-ExchangeCertificate -GenerateRequest `
  -SubjectName 'CN=mail.corp.example' `
  -DomainName mail.corp.example,autodiscover.corp.example,exch01.corp.example `
  -PrivateKeyExportable $true
Set-Content -Path C:\req.txt -Value $req
# submit C:\req.txt to your CA (WebServer template), then import the issued cert:
Import-ExchangeCertificate -FileData ([byte[]](Get-Content C:\issued.cer -Encoding byte))
Get-ExchangeCertificate | Where-Object {$_.Subject -like '*mail.corp.example*'} |
  Enable-ExchangeCertificate -Services IIS,SMTP
```

> AD FS and Keycloak each need their own server-auth cert too (subject `sts.corp.example` /
> `kc.corp.example`) - see [02-adfs-keycloak.md](02-adfs-keycloak.md).

### Trust

Every client (Windows, macOS, iOS) must trust your internal CA **root** certificate, or the
TLS handshake to HAProxy fails. Distribute the root via GPO (domain machines) and a
configuration profile / Keychain (macOS/iOS).

## Network

- Exchange, AD FS, Keycloak reachable from HAProxy.
- Clients reach only HAProxy on 443.
- For mobile EAS from outside the isolated network, HAProxy needs a second interface on the
  reachable network (see [07-eas-mobile.md](07-eas-mobile.md)).
