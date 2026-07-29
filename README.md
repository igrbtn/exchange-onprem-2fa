# Exchange on-prem 2FA with AD FS + Keycloak (TOTP)

Add real two-factor authentication (TOTP) to **Microsoft Exchange Server on-premises**
without Azure AD / Entra ID. Browser clients (OWA/ECP) and rich clients (Outlook desktop,
macOS/iOS Mail) authenticate through **AD FS**, which delegates the login to an external
identity provider - **Keycloak** - that enforces TOTP. Everything sits behind an
**HAProxy** reverse proxy (SSL bridging) with an optional **Coraza WAF**.

This is a field-tested reference build. It complements Microsoft's
[Enable modern authentication in Exchange Server on-premises](https://learn.microsoft.com/en-us/exchange/plan-and-deploy/post-installation-tasks/enable-modern-auth-in-exchange-server-on-premises)
with the dozen non-obvious gotchas that the official guide leaves out (see
[docs/09-troubleshooting.md](docs/09-troubleshooting.md)).

> Author: **Igor Batin** ([@igrbtn](https://github.com/igrbtn) - [batin.uz](https://batin.uz)).
> Licensed under MIT - attribution required (keep the copyright notice).

---

## Why this exists

Microsoft's cloud story for MFA is Entra ID. On-premises Exchange has **no native MFA**:
OWA forms auth and Basic auth for rich clients are single-factor. The supported path to add
MFA on-prem is *claims/OAuth via AD FS* - but AD FS itself has no built-in TOTP. This project
chains a standards-based IdP (Keycloak) behind AD FS as a **Claims Provider Trust**, so:

- **OWA / ECP** redirect to AD FS -> Keycloak -> password + TOTP.
- **Outlook desktop, EWS, MAPI, EAS, OAB** use OAuth 2.0 -> AD FS -> Keycloak -> password + TOTP.
- No cloud dependency, no per-user Entra licensing, self-hosted TOTP.

## Architecture

```
Client --443/TLS--> HAProxy (SSL bridging, WAF) --re-encrypt--> backends:
    mail / owa / ecp / autodiscover.corp.example -> Exchange
    sts.corp.example                             -> AD FS
    kc.corp.example                              -> Keycloak (TOTP)

AD FS  --Claims Provider Trust (SAML)-->  Keycloak  --LDAP-->  Active Directory
```

The diagram shows the default mode (HAProxy + Keycloak). Both the proxy and the second-factor
engine are swappable - see [Modes and paths](#modes-and-paths).

Three independent enforcement layers:

| Layer | Clients | Mechanism |
| --- | --- | --- |
| 1. Browser | OWA, ECP | WS-Federation claims -> AD FS -> Keycloak -> TOTP |
| 2. WAF | OWA web surface | Coraza + OWASP CRS v4 (DetectionOnly -> On) |
| 3. Rich client | Outlook, EWS, MAPI, EAS, OAB | OAuth 2.0 -> AD FS -> Keycloak -> TOTP |

## Client support matrix

| Protocol | Modern auth | | Client | Modern auth |
| --- | --- | --- | --- | --- |
| MAPI/HTTP | Yes | | Outlook Classic (Win) | Yes |
| EWS | Yes | | macOS Mail | Yes |
| EAS | Yes | | iOS Mail | Yes |
| OAB | Yes | | Outlook New (Win) | Falls back to Basic |
| RPC/HTTP | No | | Outlook iOS/Android | Falls back to Basic |
| IMAP / POP | No | | Gmail app | Falls back to Basic |

Rich-client modern auth on Windows **requires Windows 11 22H2+** (OS-level WAM broker) and
Outlook M365 Apps / 2021 Retail 2304+. See [docs/01-prerequisites.md](docs/01-prerequisites.md).

## Modes and paths

Two independent choices - the **second-factor engine** and the **reverse proxy** - combine
freely. All are field-tested on the same lab.

### Second-factor engine (how TOTP is enforced)

| Mode | How | External components | Guide |
| --- | --- | --- | --- |
| **Keycloak** (external IdP) | AD FS delegates auth to Keycloak (SAML CPT); Keycloak enforces TOTP | a Keycloak server | [02](docs/02-adfs-keycloak.md) |
| **Native AD FS TOTP** | AD FS does the AD password + TOTP itself via an MFA adapter (adfsmfa); no external IdP, no SAML | none (AD attribute storage) | [11](docs/11-native-adfs-totp.md) |

### Reverse proxy (how clients reach the backends)

| Path | Notes | Guide |
| --- | --- | --- |
| **HAProxy** (default) | Linux, SSL bridging, Coraza WAF, security headers, rate limiting; handles the OWA WebSocket | [04](docs/04-haproxy-ssl-bridging.md) |
| **AD FS WAP** | Microsoft's native AD FS proxy on Windows; no WAF; **browser OWA hangs on the notification WebSocket** - front OWA with HAProxy | [10](docs/10-wap-variant.md) |
| **Hybrid** | HAProxy in front of WAP - keeps the WAF + WebSocket handling and the supported AD FS proxy | [10](docs/10-wap-variant.md) |

### Which to pick

- **Fastest working baseline:** HAProxy + Keycloak - follow [02](docs/02-adfs-keycloak.md) -> [08](docs/08-keycloak-login-theme.md).
- **No external IdP:** HAProxy + Native AD FS TOTP - do the Exchange/proxy setup ([03](docs/03-exchange-modern-auth.md)-[05](docs/05-browser-owa-ecp.md)) then [11](docs/11-native-adfs-totp.md) instead of the Keycloak steps.
- **Microsoft-native proxy:** WAP + either engine - [10](docs/10-wap-variant.md). Because browser OWA hangs on WAP's WebSocket, use the **hybrid** (HAProxy in front) for the OWA path; rich clients (Outlook/EAS) work on WAP directly.

## Repository layout

```
docs/     step-by-step guides (00..11)
scripts/  PowerShell (AD FS, Exchange, client, WAP, adfs-mfa) + Keycloak helpers
config/   HAProxy, Coraza WAF, Keycloak login theme (templates)
```

## Quick start

This is the default path (HAProxy + Keycloak). For the other modes, see [Modes and paths](#modes-and-paths) above.

1. Read [docs/00-overview.md](docs/00-overview.md) and [docs/01-prerequisites.md](docs/01-prerequisites.md).
2. Second-factor engine - pick one: **Keycloak** [docs/02-adfs-keycloak.md](docs/02-adfs-keycloak.md), or **native AD FS TOTP** [docs/11-native-adfs-totp.md](docs/11-native-adfs-totp.md) (no external IdP).
3. Enable modern auth on Exchange: [docs/03-exchange-modern-auth.md](docs/03-exchange-modern-auth.md).
4. Put a reverse proxy in front: [docs/04-haproxy-ssl-bridging.md](docs/04-haproxy-ssl-bridging.md) (HAProxy) or [docs/10-wap-variant.md](docs/10-wap-variant.md) (AD FS WAP / hybrid).
5. Wire browser 2FA (OWA/ECP): [docs/05-browser-owa-ecp.md](docs/05-browser-owa-ecp.md).
6. Wire rich-client 2FA (Outlook): [docs/06-rich-client-outlook.md](docs/06-rich-client-outlook.md).
7. Mobile EAS + Keycloak theming: [docs/07-eas-mobile.md](docs/07-eas-mobile.md), [docs/08-keycloak-login-theme.md](docs/08-keycloak-login-theme.md).
8. When something breaks: [docs/09-troubleshooting.md](docs/09-troubleshooting.md) (+ the per-variant troubleshooting in [10](docs/10-wap-variant.md)/[11](docs/11-native-adfs-totp.md)).

## Naming convention used in docs

The guides use placeholder names - substitute your own:

| Placeholder | Meaning | Example |
| --- | --- | --- |
| `corp.example` | AD DNS domain | your AD forest |
| `CORP` | NetBIOS domain | your NetBIOS name |
| `sts.corp.example` | AD FS service FQDN | |
| `kc.corp.example` | Keycloak FQDN | |
| `mail.corp.example` | Exchange namespace | |
| `10.0.0.x` | example IPs | your subnet |

Passwords, thumbprints, and client secrets are always placeholders like
`<STRONG_PASSWORD>` / `<THUMBPRINT>`. **Never commit real secrets.**

## Status

Validated end-to-end: OWA/ECP browser TOTP, Coraza WAF on OWA, Outlook Classic modern auth
(MAPI + EWS OAuth), macOS/iOS Mail EAS. Contributions and issues welcome.

## License

MIT (c) 2026 Igor Batin. Attribution required - keep the copyright notice. See [LICENSE](LICENSE).
