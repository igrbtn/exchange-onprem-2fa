# Scripts

All scripts are parameterized with placeholder defaults (`corp.example`, `CORP`, `sts...`).
Edit the parameters (or pass them) for your environment. **No secrets are stored in any
script** - credentials come from your secret store / env vars at runtime.

Run order:

| Step | Script | Where |
| --- | --- | --- |
| 1 | `keycloak/create-saml-client.sh` | host with kcadm |
| 2 | `adfs/setup-claims-provider-trust.ps1` | AD FS server |
| 3 | `exchange/configure-modern-auth.ps1` | Exchange (EMS) |
| 4 | `adfs/add-application-group-outlook.ps1` | AD FS server |
| 5 | `adfs/add-relying-party-owa-ecp.ps1` | AD FS server |
| 6 | `exchange/configure-owa-ecp-adfs.ps1` | Exchange (EMS) |
| 7 | `client/enable-modern-auth-client.ps1` | Windows 11 client |

PowerShell scripts assume the AD FS module / Exchange Management Shell is available. The shell
script needs `kcadm.sh` on PATH and Keycloak admin credentials in environment variables.

## WAP variant (alternative to HAProxy)

If you use AD FS Web Application Proxy instead of HAProxy (see
[../docs/10-wap-variant.md](../docs/10-wap-variant.md)), run these on the WAP server (workgroup)
and the AD FS server:

| Step | Script | Where |
| --- | --- | --- |
| a | `wap/import-certs.ps1` | WAP server |
| b | `wap/install-wap.ps1` | WAP server |
| c | `wap/publish-apps.ps1` | WAP server |
| d | `wap/harden-wap-schannel.ps1` (then reboot) | WAP server |
| e | `wap/harden-adfs.ps1` | AD FS server |
