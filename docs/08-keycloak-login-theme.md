# 08 - Keycloak login theme

Customize the Keycloak login page so it looks like a corporate sign-in rather than default
Keycloak, and - critically - so it renders inside the Outlook/embedded WebView.

Templates: [../config/keycloak-theme/](../config/keycloak-theme/).

## Why a custom classic FTL theme (not keycloak.v2)

The default Keycloak 26 login theme (`keycloak.v2`) is a React app. It does **not** render in
the embedded WebView that Outlook uses for the modern-auth popup - the user sees a blank page.
A custom theme with `parent=keycloak` (the classic FreeMarker/FTL theme, server-rendered)
renders everywhere. That is the whole reason for this theme.

## Layout

```
themes/corp/login/
  theme.properties           # parent=keycloak + styles=css/custom.css
  login.ftl                  # custom login form (English labels, hint, footer)
  resources/css/custom.css   # corporate look (light, centered card)
```

Set the realm login theme to `corp` (Realm settings -> Themes -> Login theme).

## Gotchas

1. `login.ftl` MUST start with `<#import "template.ftl" as layout>`. Keycloak does not
   auto-import `layout` for a custom theme; without it FreeMarker throws "layout is null".
2. While developing, disable the theme cache so edits show up immediately - start Keycloak
   with:
   ```
   --spi-theme-cache-themes=false --spi-theme-cache-templates=false
   ```
   Re-enable caching for production.
3. Test the render with a real login flow (valid `client_id` + `redirect_uri`, append
   `&prompt=login`). Hitting the endpoint without valid params returns an error/redirect page,
   not the login form - which looks like a broken theme but is not.

## What the template does

- English labels: "Username" / "Password" / "Sign in".
- Placeholder hint "Use UPN or Email" and a small hint line under the username field.
- Centered company name header, smaller card and fonts (light, OWA-classic style).
- A small footer link (bottom-right) to the company site.
- Hides Keycloak's registration/info footers.

See [../config/keycloak-theme/login/login.ftl](../config/keycloak-theme/login/login.ftl) and
[../config/keycloak-theme/login/resources/css/custom.css](../config/keycloak-theme/login/resources/css/custom.css).
