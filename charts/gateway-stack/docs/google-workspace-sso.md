# Google Workspace SSO Setup for Guardian Control Plane

This guide sets up Google Workspace SSO for the Guardian control-plane and console stack.

## Scope

- User login/session for `control-plane` and `console`.
- Member management and local agent onboarding from the console.
- Agent runtime identity stays unchanged: agents still authenticate to `llm-gateway` with RFC 9421 signatures using `did:key`.

## 1. Decide Your External URLs

Use one control-plane host and choose whether the API is rooted at `/` or a prefix like `/api`.

Recommended (UI + API on same host):

- `ingress.hosts.controlPlane=guardian.example.com`
- `ingress.controlPlanePath=/api`
- `controlPlane.apiBasePath=/api`
- `guardianUI.runtime.apiURL=https://guardian.example.com/api`
- Google callback URL:
  - `https://guardian.example.com/api/v1/auth/callback/google`

If `ingress.controlPlanePath=/`, callback becomes:

- `https://guardian.example.com/v1/auth/callback/google`

`ingress.controlPlanePath` and `controlPlane.apiBasePath` must match.

## 2. Create the Google OAuth Client

1. In Google Cloud Console, create/select the project for Guardian.
2. Configure OAuth consent screen.
3. For Workspace-only access, choose internal user type.
4. Add scopes: `openid`, `profile`, `email`.
5. Create OAuth Client ID:
   - Application type: `Web application`
   - Authorized redirect URI: your callback URL from step 1.
6. Save:
   - `client_id`
   - `client_secret`

## 3. Generate Required Guardian Secrets

```bash
openssl rand -base64 48 | tr -d '\n'   # controlPlane.auth.stateSecret
openssl rand -base64 48 | tr -d '\n'   # controlPlane.auth.registrationTokenSecret
```

- `stateSecret`: signs OAuth state/nonce envelope.
- `registrationTokenSecret`: mints short-lived member registration tokens for local `viper did register`.
- `registrationTokenSecret` is also used by llm-gateway to validate registration tokens.
- Configure `controlPlane.auth.bearer.*` for CLI/tool OIDC bearer auth.

## 4. Configure Helm Values

Option A (recommended): reference an existing Kubernetes Secret:

```yaml
controlPlane:
  apiBasePath: /api
  auth:
    enabled: true
    existingSecret: guardian-control-plane-auth
    registrationTokenIssuer: control-plane
    bearer:
      enabled: true
      issuerURL: https://accounts.google.com
      clientID: "<google-device-client-id>"
      scopes:
        - openid
        - profile
        - email
    cookieSecure: true
    allowedEmailDomains:
      - example.com
    bootstrapAdminEmail: admin@example.com
    uiBaseURL: https://guardian.example.com
    google:
      enabled: true
      issuerURL: https://accounts.google.com
      redirectURL: https://guardian.example.com/api/v1/auth/callback/google
      scopes:
        - openid
        - profile
        - email
```

Create that Secret (default key names shown):

```bash
kubectl -n guardian create secret generic guardian-control-plane-auth \
  --from-literal=stateSecret='<strong-random-secret>' \
  --from-literal=registrationTokenSecret='<strong-random-secret>' \
  --from-literal=googleClientID='<google-client-id>' \
  --from-literal=googleClientSecret='<google-client-secret>'
```

Option B: inline values (chart creates the Secret for you):

```yaml
controlPlane:
  apiBasePath: /api
  auth:
    enabled: true
    cookieSecure: true
    allowedEmailDomains:
      - example.com
    bootstrapAdminEmail: admin@example.com
    stateSecret: "<strong-random-secret>"
    registrationTokenSecret: "<strong-random-secret>"
    registrationTokenIssuer: control-plane
    bearer:
      enabled: true
      issuerURL: https://accounts.google.com
      clientID: "<google-device-client-id>"
      scopes:
        - openid
        - profile
        - email
    uiBaseURL: https://guardian.example.com
    google:
      enabled: true
      issuerURL: https://accounts.google.com
      clientID: "<google-client-id>"
      clientSecret: "<google-client-secret>"
      redirectURL: https://guardian.example.com/api/v1/auth/callback/google
      scopes:
        - openid
        - profile
        - email

ingress:
  enabled: true
  controlPlanePath: /api
  hosts:
    controlPlane: guardian.example.com

guardianUI:
  enabled: true
  runtime:
    apiURL: https://guardian.example.com/api
    basePath: /
```

Notes:

- Keep `cookieSecure: true` in production (HTTPS required).
- `allowedEmailDomains` is the server-side domain gate.
- `bootstrapAdminEmail` is promoted to admin on first successful login.
- Secret key names are configurable via `controlPlane.auth.secretKeys.*`.
- `llmGateway.registration.enabled=true` uses `registrationTokenSecret` from the same auth secret.

## 5. Deploy

```bash
helm dependency update charts/gateway-stack
helm upgrade --install guardian charts/gateway-stack \
  --namespace guardian \
  --create-namespace \
  -f <your-values>.yaml
```

## 6. Validate SSO

1. Provider discovery returns Google:

```bash
curl -sS https://guardian.example.com/api/v1/auth/providers | jq
```

Expected provider:

```json
{
  "id": "google",
  "display_name": "Google"
}
```

2. Open the console and click `Continue with Google`.
3. Complete login and confirm console loads authenticated pages.
4. Confirm user profile endpoint in browser/devtools:
   - `GET /api/v1/me` returns `200`.

## 7. Validate Member Local Agent Onboarding

1. Sign in as a member user.
2. In console, open `Register Local Agent`.
3. Generate the registration command.
4. On the member machine:

```bash
viper did add
viper did assign --app <app>
viper did register --app <app> --provisioning-token "<generated-token>"
```

Replace `<app>` with the target agent application (`claude`, `codex`, `opencode`, `openclaw`, or `proxy`).

5. Confirm the agent appears in the console `Agents` view.

The control-plane now generates user-scoped agent IDs server-side, so users do not provide custom `agent_id`.

## 8. Non-Helm Environment Variable Equivalents

If you run control-plane without Helm, these map to the same config:

- `CONTROL_PLANE_CONFIG_FILE=/path/to/runtime.toml` (optional)
- `CONTROL_PLANE_AUTH_ENABLED=true`
- `CONTROL_PLANE_AUTH_ALLOWED_EMAIL_DOMAINS=example.com`
- `CONTROL_PLANE_AUTH_BOOTSTRAP_ADMIN_EMAIL=admin@example.com`
- `CONTROL_PLANE_AUTH_STATE_SECRET=<secret>`
- `CONTROL_PLANE_AUTH_REGISTRATION_TOKEN_SECRET=<secret>`
- `CONTROL_PLANE_AUTH_REGISTRATION_TOKEN_ISSUER=control-plane`
- `CONTROL_PLANE_AUTH_UI_BASE_URL=https://guardian.example.com`
- `CONTROL_PLANE_AUTH_GOOGLE_ENABLED=true`
- `CONTROL_PLANE_AUTH_GOOGLE_ISSUER_URL=https://accounts.google.com`
- `CONTROL_PLANE_AUTH_GOOGLE_CLIENT_ID=<client-id>`
- `CONTROL_PLANE_AUTH_GOOGLE_CLIENT_SECRET=<client-secret>`
- `CONTROL_PLANE_AUTH_GOOGLE_REDIRECT_URL=https://guardian.example.com/api/v1/auth/callback/google`
- `CONTROL_PLANE_AUTH_GOOGLE_SCOPES=openid,profile,email`
- `CONTROL_PLANE_AUTH_BEARER_ENABLED=true`
- `CONTROL_PLANE_AUTH_BEARER_ISSUER_URL=https://accounts.google.com`
- `CONTROL_PLANE_AUTH_BEARER_CLIENT_ID=<google-device-client-id>`
- `CONTROL_PLANE_AUTH_BEARER_SCOPES=openid,profile,email`

## 9. Common Issues

- `redirect_uri_mismatch`: Google redirect URI does not exactly match `controlPlane.auth.google.redirectURL`.
- `provider is not configured`: auth enabled but `google.enabled` or client settings are missing.
- `email domain is not allowed`: user email domain is not in `allowedEmailDomains`.
- Login loop/no session cookie: HTTPS/cookie domain/path mismatch.
- Callback 404: `ingress.controlPlanePath` and `controlPlane.apiBasePath` are not aligned.

## 10. Extending to Future Providers

Current production path is Google Workspace.
The control-plane auth provider model is adapter-friendly, so Entra ID/Okta can be added later without changing member/agent onboarding flow or RFC 9421 agent identity behavior.
