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

  // Service-account users that reach post-login (e.g. interactive login rather
  // than the M2M flow skipped above) still need their tokens enriched
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

    // Auth Service reads the account's organization and grants from its service_accounts row
    console.log(
      `Service account token enriched: ${serviceAccountName} (${environment} environment)`,
    );

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

  // Auth Service chooses the active organization: the login's Auth0 Organization, else its default
  let response;
  try {
    response = await fetch(
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
          auth0_organization_id: auth0OrgId,
        }),
      },
    );
  } catch (error) {
    console.error("Claims enrichment error:", error);
    api.access.deny("Sign-in failed. Try again.");
    return;
  }

  if (response.status === 403) {
    api.access.deny("You aren't a member of this organization in Guardian.");
    return;
  }
  if (!response.ok) {
    console.error(
      "Claims enrichment failed:",
      response.status,
      await response.text(),
    );
    api.access.deny("Sign-in failed. Try again.");
    return;
  }

  const claims = (await response.json()).custom_claims;
  const setClaim = (name, value) => {
    api.idToken.setCustomClaim(`${namespace}${name}`, value);
    api.accessToken.setCustomClaim(`${namespace}${name}`, value);
  };

  // Organization and role claims, as Auth Service built them
  if (claims.app_organizations && claims.app_organizations.length > 0) {
    setClaim("organizations", claims.organizations);
    setClaim("roles", claims.roles);
    // IMPORTANT: auth-service middleware requires the app_organizations claim
    setClaim("app_organizations", claims.app_organizations);
    api.idToken.setCustomClaim(
      `${namespace}organization_details`,
      claims.app_organizations,
    );

    // Auth0 organization IDs power UI organization switching
    if (claims.auth0_organizations && claims.auth0_organizations.length > 0) {
      setClaim("auth0_organizations", claims.auth0_organizations);
    }
  }

  if (claims.organization_id) {
    setClaim("organization_id", claims.organization_id);
  }
  if (claims.auth0_organization_id) {
    setClaim("auth0_organization_id", claims.auth0_organization_id);
  }

  // Project claims
  if (claims.app_projects && claims.app_projects.length > 0) {
    setClaim(
      "projects",
      claims.app_projects.map((proj) => proj.id),
    );
    // IMPORTANT: auth-service middleware requires the app_projects claim
    setClaim("app_projects", claims.app_projects);
  }

  setClaim("has_admin_access", claims.has_admin_access || false);

  // DID key is created automatically on first login by auth-service
  if (claims.did_key_id) {
    setClaim("did_key_id", claims.did_key_id);
  }

  // Standard identity claims (email, user_id, name, picture)
  setClaim("email", event.user.email);
  setClaim("user_id", event.user.user_id);
  setClaim("picture", event.user.picture || "");
  api.idToken.setCustomClaim(
    `${namespace}email_verified`,
    event.user.email_verified,
  );
  api.accessToken.setCustomClaim(
    `${namespace}name`,
    event.user.name || event.user.nickname || event.user.email,
  );

  // The active organization's context as Auth Service built it, so it always names organization_id's
  if (claims.auth0_org_context) {
    setClaim("auth0_org_context", claims.auth0_org_context);
  }
};
