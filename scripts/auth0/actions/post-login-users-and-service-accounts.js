/**
 * Auth0 Action: Post Login Users & Service Accounts
 * Trigger: Post Login
 *
 * This action enriches user and service account tokens with organization,
 * role, and project claims during the post-login flow.
 *
 * @param {Event} event - Details about the user and the context in which they are logging in.
 * @param {PostLoginAPI} api - Interface whose methods can be used to change the behavior of the login.
 */
exports.onExecutePostLogin = async (event, api) => {
  // Skip for Machine-to-Machine apps (they use client credentials flow)
  if (event.client.metadata?.type === "m2m") {
    return;
  }

  // Resolve the auth-service URL for this environment, falling back to dev
  const environment = event.client.metadata?.environment || "dev";

  const AUTH_SERVICE_URLS = {
    dev: event.secrets.AUTH_SERVICE_URL_DEV,
    staging: event.secrets.AUTH_SERVICE_URL_STAGING,
    production: event.secrets.AUTH_SERVICE_URL_PRODUCTION,
  };

  const AUTH_SERVICE_URL =
    AUTH_SERVICE_URLS[environment] ||
    AUTH_SERVICE_URLS.dev ||
    event.secrets.AUTH_SERVICE_URL;

  console.log(
    `Auth0 Action: Using ${environment} environment with URL: ${AUTH_SERVICE_URL}`,
  );

  const API_SECRET = event.secrets.AUTH_SERVICE_API_SECRET;
  const namespace = "https://governance.eqtylab.io/";

  const auth0OrgId = event.organization?.id;
  const auth0OrgName = event.organization?.name;
  const auth0OrgDisplayName = event.organization?.display_name;

  // Service-account users that reach post-login (e.g. interactive login rather
  // than the M2M flow handled at line 13) still need their tokens enriched
  const isServiceAccount = event.user.app_metadata?.is_service_account === true;

  if (isServiceAccount) {
    const serviceAccountName =
      event.user.app_metadata?.service_account_name || event.user.email;
    const serviceAccountId = event.user.user_id;
    const serviceType = event.user.app_metadata?.service_type || "unknown";

    // Identity claims
    api.accessToken.setCustomClaim(`${namespace}is_service_account`, true);
    api.accessToken.setCustomClaim(
      `${namespace}service_account_name`,
      serviceAccountName,
    );
    api.accessToken.setCustomClaim(`${namespace}service_type`, serviceType);
    api.accessToken.setCustomClaim(
      `${namespace}auth0_user_id`,
      serviceAccountId,
    );

    // Service accounts need a special sub claim for DID key lookup
    api.accessToken.setCustomClaim("sub", serviceAccountId);

    // Platform-wide service accounts have no organization binding
    const isPlatformWide = !event.user.app_metadata?.organization_id;

    if (isPlatformWide) {
      // Platform-wide claims: wildcard org access and platform-level roles
      api.accessToken.setCustomClaim(`${namespace}platform_access`, true);
      api.accessToken.setCustomClaim(`${namespace}organizations`, ["*"]);

      const platformRoles = [
        "platform:service_account",
        "governance:declarations:create",
      ];
      api.accessToken.setCustomClaim(`${namespace}roles`, platformRoles);

      console.log(
        `Platform-wide service account token enriched: ${serviceAccountName} (${environment} environment)`,
      );
    } else {
      // Org-scoped claims; organization_id is stored as a string in app_metadata, auth-service expects integers
      const orgId = parseInt(event.user.app_metadata.organization_id, 10);
      api.accessToken.setCustomClaim(`${namespace}organization_id`, orgId);
      api.accessToken.setCustomClaim(`${namespace}organizations`, [orgId]);

      const orgRoles = ["service_account", "governance:declarations:create"];
      api.accessToken.setCustomClaim(`${namespace}roles`, orgRoles);

      console.log(
        `Organization-scoped service account token enriched: ${serviceAccountName} (${environment} environment)`,
      );
    }

    // DID key claim
    if (event.user.app_metadata?.did_key_id) {
      api.accessToken.setCustomClaim(
        `${namespace}did_key_id`,
        event.user.app_metadata.did_key_id,
      );
    }

    return;
  }

  // Regular user flow - only proceed for verified emails
  if (!event.user.email_verified) {
    api.access.deny("Please verify your email address.");
    return;
  }

  try {
    // Fetch enrichment claims (organizations, roles, projects, etc.) from auth-service
    const response = await fetch(
      `${AUTH_SERVICE_URL}/api/v1/auth/claims-enrichment`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${API_SECRET}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          user_id: event.user.user_id,
          email: event.user.email,
          name: event.user.name || event.user.nickname || event.user.email,
          picture: event.user.picture,
          provider: "auth0",
        }),
      },
    );

    if (response.ok) {
      const data = await response.json();
      const claims = data.custom_claims;

      // Organization and role claims
      if (claims.app_organizations && claims.app_organizations.length > 0) {
        const orgIds = claims.app_organizations.map((org) => org.id);
        const auth0OrgIds = claims.app_organizations
          .filter((org) => org.auth0_org_id)
          .map((org) => org.auth0_org_id);
        const roles = [];

        claims.app_organizations.forEach((org) => {
          if (org.roles && org.roles.length > 0) {
            org.roles.forEach((role) => {
              // auth-service expects scoped roles in the format "role_name:org_id"
              roles.push(`${role}:${org.id}`);
              // Also emit the unscoped role for backward compatibility
              roles.push(role);
            });
          }
        });

        const uniqueRoles = [...new Set(roles)];

        api.idToken.setCustomClaim(`${namespace}organizations`, orgIds);
        api.accessToken.setCustomClaim(`${namespace}organizations`, orgIds);

        // Auth0 organization IDs power UI organization switching
        if (auth0OrgIds.length > 0) {
          api.idToken.setCustomClaim(
            `${namespace}auth0_organizations`,
            auth0OrgIds,
          );
          api.accessToken.setCustomClaim(
            `${namespace}auth0_organizations`,
            auth0OrgIds,
          );
        }

        // Full organization details consumed by the UI
        api.idToken.setCustomClaim(
          `${namespace}organization_details`,
          claims.app_organizations,
        );

        api.idToken.setCustomClaim(`${namespace}roles`, uniqueRoles);
        api.accessToken.setCustomClaim(`${namespace}roles`, uniqueRoles);

        // IMPORTANT: auth-service middleware requires the app_organizations claim
        api.accessToken.setCustomClaim(
          `${namespace}app_organizations`,
          claims.app_organizations,
        );
        api.idToken.setCustomClaim(
          `${namespace}app_organizations`,
          claims.app_organizations,
        );

        // Resolve the default organization for this login
        if (auth0OrgId) {
          // User logged in through a specific Auth0 org — resolve it to the internal org id
          let _orgId = 0;
          let _auth0OrgId = "";
          claims.app_organizations.forEach((org) => {
            if (org.auth0_org_id === auth0OrgId) {
              _orgId = org.id;
              _auth0OrgId = org.auth0_org_id;
            }
          });

          api.idToken.setCustomClaim(`${namespace}organization_id`, _orgId);
          api.accessToken.setCustomClaim(`${namespace}organization_id`, _orgId);

          api.idToken.setCustomClaim(
            `${namespace}auth0_organization_id`,
            _auth0OrgId,
          );
          api.accessToken.setCustomClaim(
            `${namespace}auth0_organization_id`,
            _auth0OrgId,
          );
        } else {
          // No Auth0 org context — default to the first org the user belongs to
          api.idToken.setCustomClaim(`${namespace}organization_id`, orgIds[0]);
          api.accessToken.setCustomClaim(
            `${namespace}organization_id`,
            orgIds[0],
          );

          if (auth0OrgIds.length > 0) {
            api.idToken.setCustomClaim(
              `${namespace}auth0_organization_id`,
              auth0OrgIds[0],
            );
            api.accessToken.setCustomClaim(
              `${namespace}auth0_organization_id`,
              auth0OrgIds[0],
            );
          }
        }
      }

      // Project claims
      if (claims.app_projects && claims.app_projects.length > 0) {
        const projectIds = claims.app_projects.map((proj) => proj.id);
        api.idToken.setCustomClaim(`${namespace}projects`, projectIds);
        api.accessToken.setCustomClaim(`${namespace}projects`, projectIds);

        // IMPORTANT: auth-service middleware requires the app_projects claim
        api.accessToken.setCustomClaim(
          `${namespace}app_projects`,
          claims.app_projects,
        );
        api.idToken.setCustomClaim(
          `${namespace}app_projects`,
          claims.app_projects,
        );
      }

      // User context claims (admin access, etc.)
      if (claims.user_context) {
        api.idToken.setCustomClaim(
          `${namespace}has_admin_access`,
          claims.user_context.has_admin_access || false,
        );
        api.accessToken.setCustomClaim(
          `${namespace}has_admin_access`,
          claims.user_context.has_admin_access || false,
        );
      }

      // DID key is created automatically on first login by auth-service
      if (claims.did_key_id) {
        api.idToken.setCustomClaim(`${namespace}did_key_id`, claims.did_key_id);
        api.accessToken.setCustomClaim(
          `${namespace}did_key_id`,
          claims.did_key_id,
        );
      }

      // Standard identity claims (email, user_id, name, picture)
      api.idToken.setCustomClaim(`${namespace}email`, event.user.email);
      api.idToken.setCustomClaim(
        `${namespace}email_verified`,
        event.user.email_verified,
      );
      api.idToken.setCustomClaim(`${namespace}user_id`, event.user.user_id);
      api.accessToken.setCustomClaim(`${namespace}user_id`, event.user.user_id);

      const name = event.user.name || event.user.nickname || event.user.email;
      const picture = event.user.picture || "";

      api.accessToken.setCustomClaim(`${namespace}email`, event.user.email);
      api.accessToken.setCustomClaim(`${namespace}name`, name);
      api.idToken.setCustomClaim(`${namespace}picture`, picture);
      api.accessToken.setCustomClaim(`${namespace}picture`, picture);

      // Auth0 organization context from the login event (only set if user logged in through an org)
      if (auth0OrgId) {
        api.idToken.setCustomClaim(`${namespace}auth0_org_context`, {
          id: auth0OrgId,
          name: auth0OrgName,
          display_name: auth0OrgDisplayName,
        });
        api.accessToken.setCustomClaim(`${namespace}auth0_org_context`, {
          id: auth0OrgId,
          name: auth0OrgName,
          display_name: auth0OrgDisplayName,
        });
      }
    } else {
      console.error("Claims enrichment failed:", response.status);
      const errorText = await response.text();
      console.error("Error response:", errorText);

      // Fall back to a minimal token so the user can still log in if auth-service is unreachable
      api.idToken.setCustomClaim(`${namespace}user_id`, event.user.user_id);
      api.accessToken.setCustomClaim(`${namespace}user_id`, event.user.user_id);
      api.idToken.setCustomClaim(`${namespace}email`, event.user.email);
      api.accessToken.setCustomClaim(`${namespace}email`, event.user.email);
    }
  } catch (error) {
    console.error("Claims enrichment error:", error);

    // Same minimal-token fallback as the !response.ok branch above
    api.idToken.setCustomClaim(`${namespace}user_id`, event.user.user_id);
    api.accessToken.setCustomClaim(`${namespace}user_id`, event.user.user_id);
    api.idToken.setCustomClaim(`${namespace}email`, event.user.email);
    api.accessToken.setCustomClaim(`${namespace}email`, event.user.email);
    api.idToken.setCustomClaim(
      "name",
      event.user.name || event.user.nickname || event.user.email,
    );
    api.accessToken.setCustomClaim(
      "name",
      event.user.name || event.user.nickname || event.user.email,
    );
  }
};
