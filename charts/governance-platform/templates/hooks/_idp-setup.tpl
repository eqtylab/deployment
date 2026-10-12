{{/*
Shared pieces of the IdP setup hook Jobs (post-install-{auth0,entra,keycloak}-setup-job.yaml).
*/}}

{{/*
Image for the IdP setup hook containers. Needs psql and pg_isready; curl and jq are installed with apk
at runtime unless the image already provides them.
*/}}
{{- define "governance-platform.idpSetup.image" -}}
{{- .Values.idpSetupImage | default "postgres:17-alpine" -}}
{{- end }}

{{/*
libpq environment for the platform database.
*/}}
{{- define "governance-platform.idpSetup.pgEnv" -}}
{{- $pgAuth := ((((.Values.postgresql).global).postgresql).auth) | default dict }}
{{- $pgSecretKeys := $pgAuth.secretKeys | default dict }}
{{- $pgSslRootCert := (((.Values.global).postgresql).sslRootCert) | default dict }}
- name: PGHOST
  value: {{ ((.Values.global).postgresql).host | default (printf "%s-postgresql" .Release.Name) | quote }}
- name: PGPORT
  value: {{ ((.Values.global).postgresql).port | default 5432 | quote }}
- name: PGUSER
  value: {{ ((.Values.global).postgresql).username | default ($pgAuth.username | default "postgres") | quote }}
- name: PGPASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ (((.Values.global).secrets).database).secretName | default ($pgAuth.existingSecret | default "platform-database") | quote }}
      key: {{ ((((.Values.global).secrets).database).keys).password | default ($pgSecretKeys.userPasswordKey | default "password") | quote }}
- name: PGDATABASE
  value: {{ ((.Values.global).postgresql).database | default ($pgAuth.database | default "governance") | quote }}
- name: PGSSLMODE
  value: {{ ((.Values.global).postgresql).sslMode | default "disable" | quote }}
{{- if or $pgSslRootCert.secretName $pgSslRootCert.configMapName }}
- name: PGSSLROOTCERT
  value: {{ printf "/etc/ssl/postgres/%s" ($pgSslRootCert.key | default "ca.crt") | quote }}
{{- end }}
{{- end }}

{{/*
volumeMounts for the database CA certificate, when one is configured.
*/}}
{{- define "governance-platform.idpSetup.pgCaVolumeMounts" -}}
{{- $pgSslRootCert := (((.Values.global).postgresql).sslRootCert) | default dict }}
{{- if or $pgSslRootCert.secretName $pgSslRootCert.configMapName }}
volumeMounts:
  - name: postgres-ca
    mountPath: /etc/ssl/postgres
    readOnly: true
{{- end }}
{{- end }}

{{/*
Pod volumes for the database CA certificate, when one is configured.
*/}}
{{- define "governance-platform.idpSetup.pgCaVolumes" -}}
{{- $pgSslRootCert := (((.Values.global).postgresql).sslRootCert) | default dict }}
{{- if $pgSslRootCert.secretName }}
volumes:
  - name: postgres-ca
    secret:
      secretName: {{ $pgSslRootCert.secretName | quote }}
      items:
        - key: {{ $pgSslRootCert.key | default "ca.crt" | quote }}
          path: {{ $pgSslRootCert.key | default "ca.crt" | quote }}
{{- else if $pgSslRootCert.configMapName }}
volumes:
  - name: postgres-ca
    configMap:
      name: {{ $pgSslRootCert.configMapName | quote }}
      items:
        - key: {{ $pgSslRootCert.key | default "ca.crt" | quote }}
          path: {{ $pgSslRootCert.key | default "ca.crt" | quote }}
{{- end }}
{{- end }}

{{/*
Init container that waits for the auth and governance migrations to create the tables the hook writes.
*/}}
{{- define "governance-platform.idpSetup.waitForSchema" -}}
- name: wait-for-schema
  image: {{ include "governance-platform.idpSetup.image" . }}
  command: ["/bin/sh", "-c"]
  args:
    - |
      echo "Waiting for database schema to be ready..."

      until pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER"; do
        echo "Waiting for database to be ready..."
        sleep 5
      done

      echo "Checking for required tables..."
      REQUIRED_TABLES="organization users user_organization_memberships user_project_assignments"
      MAX_ATTEMPTS=30
      ATTEMPT=1

      while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
        ALL_EXIST=true
        for TABLE in $REQUIRED_TABLES; do
          EXISTS=$(psql -X -tA -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = '$TABLE');")

          if [ "$EXISTS" != "t" ]; then
            ALL_EXIST=false
            echo "Table $TABLE does not exist yet..."
            break
          fi
        done

        if [ "$ALL_EXIST" = "true" ]; then
          echo "All required tables exist!"
          exit 0
        fi

        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS - Waiting 10 seconds for migrations..."
        sleep 10
        ATTEMPT=$((ATTEMPT + 1))
      done

      echo "Warning: Some tables may not exist, but proceeding..."
      exit 0
  env:
    {{- include "governance-platform.idpSetup.pgEnv" . | nindent 4 }}
  {{- include "governance-platform.idpSetup.pgCaVolumeMounts" . | nindent 2 }}
{{- end }}

{{/*
Shell functions shared by the hook scripts. Inputs arrive as environment variables, never as template
text, so values containing quotes cannot break the shell or the SQL.

  upsert_org    reads ORG_NAME, ORG_DISPLAY_NAME, IDP_PROVIDER; sets ORG_ID
  upsert_admin  reads ORG_ID, IDP_PROVIDER, IDP_USER_ID, ADMIN_EMAIL, ADMIN_DISPLAY_NAME,
                ADMIN_GIVEN_NAME, ADMIN_FAMILY_NAME

The SQL here is mirrored in scripts/helpers/idp-setup.sh for the standalone setup scripts.
*/}}
{{- define "governance-platform.idpSetup.shellLib" -}}
set -eu

# Run SQL with errors fatal and unaligned, header-free output
sql() {
  psql -X -q -v ON_ERROR_STOP=1 -tA "$@"
}

# Render a value as a SQL string literal
lit() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"
}

# Install curl and jq unless the image already provides them
ensure_http_tools() {
  if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    apk add --no-cache curl jq >/dev/null
  fi
}

wait_for_db() {
  echo "Waiting for database to be ready..."
  until pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER"; do
    echo "Database not ready yet..."
    sleep 5
  done
}

# Create the organization, or point an existing one at this IdP. display_name is only set on create.
upsert_org() {
  ORG_ID=$(sql -c "SELECT id FROM organization WHERE name = $(lit "$ORG_NAME") ORDER BY id LIMIT 1;")
  if [ -n "$ORG_ID" ]; then
    sql -c "UPDATE organization SET idp_provider = $(lit "$IDP_PROVIDER"), updated_at = NOW() WHERE id = $ORG_ID;"
    echo "Organization '$ORG_NAME' already exists; set idp_provider to $IDP_PROVIDER"
  else
    ORG_ID=$(sql -c "INSERT INTO organization (name, description, display_name, idp_provider) \
      VALUES ($(lit "$ORG_NAME"), $(lit "$ORG_NAME"), $(lit "$ORG_DISPLAY_NAME"), $(lit "$IDP_PROVIDER")) RETURNING id;")
    echo "Created organization '$ORG_NAME'"
  fi
  psql -X -c "SELECT id, name, display_name, idp_provider FROM organization WHERE id = $ORG_ID;"
}

# Create the platform admin user if missing, link it to the IdP account and make it an active
# organization owner. Existing organization roles are kept; project roles and project assignments in
# the organization are dropped because organization owners cannot hold them.
upsert_admin() {
  USER_ID=$(sql -c "SELECT id FROM users \
    WHERE email = $(lit "$ADMIN_EMAIL") \
       OR (idp_provider = $(lit "$IDP_PROVIDER") AND idp_user_id = $(lit "$IDP_USER_ID")) \
    ORDER BY (idp_provider = $(lit "$IDP_PROVIDER") AND idp_user_id = $(lit "$IDP_USER_ID")) DESC \
    LIMIT 1;")
  if [ -n "$USER_ID" ]; then
    echo "Platform admin user already exists"
    # Point a row found by email at this IdP account (another IdP, a recreated IdP user, or the
    # placeholder IdP user ID written by older setup scripts)
    LINKED=$(sql -c "UPDATE users SET idp_provider = $(lit "$IDP_PROVIDER"), idp_user_id = $(lit "$IDP_USER_ID"), \
        updated_at = NOW() \
      WHERE id = '$USER_ID' \
        AND NOT (idp_provider = $(lit "$IDP_PROVIDER") AND idp_user_id = $(lit "$IDP_USER_ID")) \
      RETURNING id;")
    if [ -n "$LINKED" ]; then
      echo "Linked platform admin user to $IDP_PROVIDER user $IDP_USER_ID"
    fi
  else
    USER_ID=$(sql -c "INSERT INTO users (idp_provider, idp_user_id, email, email_verified, display_name, given_name, family_name, active) \
      VALUES ($(lit "$IDP_PROVIDER"), $(lit "$IDP_USER_ID"), $(lit "$ADMIN_EMAIL"), true, \
              $(lit "$ADMIN_DISPLAY_NAME"), $(lit "$ADMIN_GIVEN_NAME"), $(lit "$ADMIN_FAMILY_NAME"), true) \
      RETURNING id;")
    echo "Created platform admin user"
  fi

  sql -c "INSERT INTO user_organization_memberships (user_id, organization_id, roles, invited_at, joined_at, status) \
    VALUES ('$USER_ID', $ORG_ID, ARRAY['organization_owner'], NOW(), NOW(), 'active') \
    ON CONFLICT (user_id, organization_id) DO UPDATE SET \
      roles = ARRAY['organization_owner'] || ARRAY( \
        SELECT r FROM unnest(user_organization_memberships.roles) AS r \
        WHERE r <> ALL (ARRAY['organization_owner', 'project_owner', 'implementation_owner', \
          'implementation_contributor', 'audit_owner', 'audit_contributor', 'project_viewer'])), \
      status = 'active', \
      joined_at = COALESCE(user_organization_memberships.joined_at, NOW());"
  sql -c "DELETE FROM user_project_assignments WHERE user_id = '$USER_ID' AND organization_id = $ORG_ID;"
  echo "Ensured organization_owner membership"

  echo "Platform admin user:"
  psql -X -c "SELECT id, email, display_name, idp_provider FROM users WHERE id = '$USER_ID';"
}
{{- end }}
