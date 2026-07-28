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

- An internal CA (Enterprise Root CA is fine) to issue web server certificates.
- One multi-SAN certificate for HAProxy covering: `mail`, `autodiscover`, `sts`, `kc`,
  `owa`, `ecp` under your domain.
- A separate certificate for Exchange itself (SAN `mail`, `autodiscover`, server FQDN).
- DNS A records for `mail`, `autodiscover`, `owa`, `ecp`, `sts`, `kc` pointing at HAProxy.
- All clients must trust your internal CA root.

## Network

- Exchange, AD FS, Keycloak reachable from HAProxy.
- Clients reach only HAProxy on 443.
- For mobile EAS from outside the isolated network, HAProxy needs a second interface on the
  reachable network (see [07-eas-mobile.md](07-eas-mobile.md)).
