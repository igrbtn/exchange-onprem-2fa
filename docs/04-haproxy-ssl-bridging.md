# 04 - HAProxy (SSL bridging)

HAProxy terminates TLS with the multi-SAN certificate, routes by Host header to Exchange /
AD FS / Keycloak, and re-encrypts to each backend. L7 mode is what makes the WAF and the
`/common/sso/*` fix possible.

Full config: [../config/haproxy/haproxy.cfg](../config/haproxy/haproxy.cfg). It is a hardened
reference, not a minimal example - review and tune it for your environment.

## Hardening included in the reference config

- **TLS**: TLS 1.2+ only, strong cipher suites, `no-tls-tickets`, HTTP -> HTTPS redirect.
- **Security headers**: HSTS, `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`.
- **Forwarding hygiene**: strips client-supplied `X-Forwarded-*` / `X-Real-Ip` before setting
  its own, so a client cannot spoof source IP or scheme.
- **Method filtering**: denies `TRACE` / `TRACK` / `CONNECT`.
- **Rate limiting**: per-source `http_req_rate` on auth paths (`/owa/auth`, `/adfs/ls`,
  `/realms`) only - never on ActiveSync/MAPI, which generate many legitimate requests.
- **Periphery lockdown**: `/ecp` and `/powershell` restricted to the management network;
  AD FS WS-Trust Windows-transport endpoints blocked from extranet; Keycloak `/admin` limited
  to trusted networks and `/health` `/metrics` never proxied.
- **Health checks** per backend (`/owa/healthcheck.htm`, `/adfs/probe`, KC OIDC discovery)
  with `inter/downinter/fall/rise` tuned against flapping.
- **Tarpit** default backend slow-drops unmatched/hostile requests.
- **Stats** bound to `127.0.0.1` only (reach via SSH tunnel), password set out-of-band.

Timeouts are deliberately long (`client`/`server` 1000s, `tunnel` 3600s) - Exchange
long-polling (ActiveSync heartbeat, MAPI/EWS hanging GET) requires it; do not shorten blindly.

## Certificate

Build a PEM (cert chain + private key) for HAProxy from your multi-SAN certificate:

```bash
openssl pkcs12 -in haproxy.pfx -nodes -out /etc/haproxy/certs/lab.pem
chmod 600 /etc/haproxy/certs/lab.pem
```

SAN must cover `mail`, `autodiscover`, `sts`, `kc`, `owa`, `ecp` under your domain.

## Routing

- `Host: sts.corp.example` -> AD FS backend (re-encrypt, SNI `sts.corp.example`).
- `Host: kc.corp.example` -> Keycloak backend (`:8080`, add `X-Forwarded-Host`).
- `Host: mail/autodiscover.corp.example` -> Exchange backend (re-encrypt, SNI `mail.corp.example`).
- anything else -> tarpit (slow-drop), not a fast 404.

Backends need `sni str(...)` and `check-sni` - AD FS and Exchange http.sys require SNI or
they answer HTTP 400 "Invalid Hostname".

## The `/common/sso/*` fix (remove the 404 flash)

After a successful rich-client login the MSAL/WAM broker navigates to
`sts.corp.example/common/sso/final` - an Azure-AD endpoint AD FS does not have, so IIS returns
404, which flashes in the Outlook popup. The broker only reads the auth code from the URL, so
authentication is not affected; return a blank 200 to hide the flash:

```
http-request return status 200 content-type "text/html" string "<!doctype html><title>ok</title>" \
    if { hdr(host) -i sts.corp.example } { path_beg /common/sso/ }
```

## Coraza WAF hook

The config wires the Coraza SPOE filter and deny rules. The WAF runs DetectionOnly first; see
[05-browser-owa-ecp.md](05-browser-owa-ecp.md) and
[../config/coraza/](../config/coraza/). WAF inspection is scoped to `/owa` and `/ecp` only -
do not inspect the binary MAPI/EAS streams (flood of false positives).

## Validate and reload

```bash
haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl reload haproxy
```

Always validate before reload. Stats page on `:9000/stats`.
