/**
 * Handler that will be called during the execution of a PostLogin flow.
 * Updated to handle service account tokens and integer IDs for organizations/projects.
 *
 * @param {Event} event - Details about the user and the context in which they are logging in.
 * @param {PostLoginAPI} api - Interface whose methods can be used to change the behavior of the login.
 */
exports.onExecutePostLogin = async (event, api) => {
  // Skip for Machine-to-Machine apps (they use client credentials flow)
  if (event.client.metadata?.type === "m2m") {
    return;
  }

  // Detect environment from client metadata
  const environment = event.client.metadata?.environment || "dev";

  // Map environment to corresponding service URL
  const AUTH_SERVICE_URLS = {
    dev: event.secrets.AUTH_SERVICE_URL_DEV,
    staging: event.secrets.AUTH_SERVICE_URL_STAGING,
    production: event.secrets.AUTH_SERVICE_URL_PRODUCTION,
  };

  // Select appropriate URL based on environment, with fallback to dev
  const AUTH_SERVICE_URL =
    AUTH_SERVICE_URLS[environment] ||
    AUTH_SERVICE_URLS.dev ||
    event.secrets.AUTH_SERVICE_URL;

  // Log environment detection for debugging
  console.log(
    `Auth0 Action: Using ${environment} environment with URL: ${AUTH_SERVICE_URL}`,
  );

  const API_SECRET = event.secrets.AUTH_SERVICE_API_SECRET;
  const namespace = "https://governance.eqtylab.io/";

  // Capture Auth0 organization context if user is logging in through an organization
  const auth0OrgId = event.organization?.id;
  const auth0OrgName = event.organization?.name;
  const auth0OrgDisplayName = event.organization?.display_name;

  // Check if this is a service account token request
  // Service accounts authenticate with client credentials flow but we need to enrich their tokens
  const isServiceAccount = event.user.app_metadata?.is_service_account === true;

  if (isServiceAccount) {
    // For service accounts, add minimal required claims
    const serviceAccountName =
      event.user.app_metadata?.service_account_name || event.user.email;
    const serviceAccountId = event.user.user_id;
    const serviceType = event.user.app_metadata?.service_type || "unknown";

    // Add service account identifier
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

    // Check if this is a platform-wide service account (no organization binding)
    const isPlatformWide = !event.user.app_metadata?.organization_id;

    if (isPlatformWide) {
      // Platform-wide service accounts get special claims
      api.accessToken.setCustomClaim(`${namespace}platform_access`, true);
      api.accessToken.setCustomClaim(`${namespace}organizations`, ["*"]); // Wildcard for all orgs

      // Add platform-wide roles
      const platformRoles = [
        "platform:service_account",
        "governance:declarations:create",
      ];
      api.accessToken.setCustomClaim(`${namespace}roles`, platformRoles);

      console.log(
        `Platform-wide service account token enriched: ${serviceAccountName} (${environment} environment)`,
      );
    } else {
      // Organization-scoped service account
      // Convert organization_id to integer if it's stored as string in app_metadata
      const orgId = parseInt(event.user.app_metadata.organization_id, 10);
      api.accessToken.setCustomClaim(`${namespace}organization_id`, orgId);
      api.accessToken.setCustomClaim(`${namespace}organizations`, [orgId]);

      // Add org-scoped roles
      const orgRoles = ["service_account", "governance:declarations:create"];
      api.accessToken.setCustomClaim(`${namespace}roles`, orgRoles);

      console.log(
        `Organization-scoped service account token enriched: ${serviceAccountName} (${environment} environment)`,
      );
    }

    // Add DID key ID if available
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
    // Call the claims enrichment endpoint
    const response = await fetch(
      `${AUTH_SERVICE_URL}/api/v1/auth/claims-enrichment`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${API_SECRET}`, // Correct format
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          user_id: event.user.user_id,
          email: event.user.email,
          name: event.user.name || event.user.nickname || event.user.email,
          picture: event.user.picture,
          provider: "auth0", // Specify the IDP provider
        }),
      },
    );

    if (response.ok) {
      const data = await response.json();
      const claims = data.custom_claims;

      // Add organization claims
      if (claims.app_organizations && claims.app_organizations.length > 0) {
        // Extract organization IDs (now integers) and Auth0 organization IDs
        const orgIds = claims.app_organizations.map((org) => org.id);
        const auth0OrgIds = claims.app_organizations
          .filter((org) => org.auth0_org_id)
          .map((org) => org.auth0_org_id);
        const roles = [];

        // Build role list from organizations
        claims.app_organizations.forEach((org) => {
          if (org.roles && org.roles.length > 0) {
            org.roles.forEach((role) => {
              // Add roles in the format expected by auth-service: "role_name:org_id"
              roles.push(`${role}:${org.id}`);
              // Also add unscoped role for backward compatibility
              roles.push(role);
            });
          }
        });

        // Remove duplicates
        const uniqueRoles = [...new Set(roles)];

        // Set organization claims
        api.idToken.setCustomClaim(`${namespace}organizations`, orgIds);
        api.accessToken.setCustomClaim(`${namespace}organizations`, orgIds);

        // Add Auth0 organization IDs for UI organization switching
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

        // Add full organization details for the UI
        api.idToken.setCustomClaim(
          `${namespace}organization_details`,
          claims.app_organizations,
        );

        // Set role claims
        api.idToken.setCustomClaim(`${namespace}roles`, uniqueRoles);
        api.accessToken.setCustomClaim(`${namespace}roles`, uniqueRoles);

        // IMPORTANT: Add app_organizations claim for auth-service middleware
        api.accessToken.setCustomClaim(
          `${namespace}app_organizations`,
          claims.app_organizations,
        );
        api.idToken.setCustomClaim(
          `${namespace}app_organizations`,
          claims.app_organizations,
        );

        if (auth0OrgId) {
          let _orgId = 0;
          let _auth0OrgId = "";
          // Build role list from organizations
          claims.app_organizations.forEach((org) => {
            if (org.auth0_org_id === auth0OrgId) {
              _orgId = org.id;
              _auth0OrgId = org.auth0_org_id;
            }
          });

          // Set default organization
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
          // Set default organization (first one)
          api.idToken.setCustomClaim(`${namespace}organization_id`, orgIds[0]);
          api.accessToken.setCustomClaim(
            `${namespace}organization_id`,
            orgIds[0],
          );

          // Set default Auth0 organization ID if available
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

      // Add project claims
      if (claims.app_projects && claims.app_projects.length > 0) {
        const projectIds = claims.app_projects.map((proj) => proj.id);
        api.idToken.setCustomClaim(`${namespace}projects`, projectIds);
        api.accessToken.setCustomClaim(`${namespace}projects`, projectIds);

        // IMPORTANT: Add app_projects claim for auth-service middleware
        api.accessToken.setCustomClaim(
          `${namespace}app_projects`,
          claims.app_projects,
        );
        api.idToken.setCustomClaim(
          `${namespace}app_projects`,
          claims.app_projects,
        );
      }

      // Add user context
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

      // Add DID key ID if available (created automatically on first login)
      if (claims.did_key_id) {
        api.idToken.setCustomClaim(`${namespace}did_key_id`, claims.did_key_id);
        api.accessToken.setCustomClaim(
          `${namespace}did_key_id`,
          claims.did_key_id,
        );
      }

      // Add standard claims
      api.idToken.setCustomClaim(`${namespace}email`, event.user.email);
      api.idToken.setCustomClaim(
        `${namespace}email_verified`,
        event.user.email_verified,
      );
      api.idToken.setCustomClaim(`${namespace}user_id`, event.user.user_id);
      api.accessToken.setCustomClaim(`${namespace}user_id`, event.user.user_id);

      const name = event.user.name || event.user.nickname || event.user.email;
      const picture = event.user.picture || "";

      // Add auth0 specific claims
      api.accessToken.setCustomClaim(`${namespace}email`, event.user.email);
      api.accessToken.setCustomClaim(`${namespace}name`, name);
      api.idToken.setCustomClaim(`${namespace}picture`, picture);

      console.log("Name", name);
      console.log("Picture", picture);

      // Add Auth0 organization context from the event (if user logged in through an organization)
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

      console.log(api.accessToken);
    } else {
      console.error("Claims enrichment failed:", response.status);
      const errorText = await response.text();
      console.error("Error response:", errorText);

      // Set minimal claims even if enrichment fails
      api.idToken.setCustomClaim(`${namespace}user_id`, event.user.user_id);
      api.accessToken.setCustomClaim(`${namespace}user_id`, event.user.user_id);
      api.idToken.setCustomClaim(`${namespace}email`, event.user.email);
      api.accessToken.setCustomClaim(`${namespace}email`, event.user.email);
    }
  } catch (error) {
    console.error("Claims enrichment error:", error);

    // Set minimal claims even if enrichment fails
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

/**
 * Handler that will be invoked when this action is resuming after an external redirect.
 * If your onExecutePostLogin function does not perform a redirect, this function can be safely ignored.
 *
 * @param {Event} event - Details about the user and the context in which they are logging in.
 * @param {PostLoginAPI} api - Interface whose methods can be used to change the behavior of the login.
 */
// exports.onContinuePostLogin = async (event, api) => {
// };
