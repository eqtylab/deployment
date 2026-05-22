/**
 * Auth0 Action: Service Account Credentials
 * Trigger: Client Credentials Exchange
 *
 * This action enriches M2M tokens with service account user information
 * when the governance-worker M2M application requests a token.
 *
 * @param {Event} event - Details about the client requesting the token.
 * @param {CredentialsExchangeAPI} api - Interface whose methods can be used to change the behavior of the credentials exchange.
 */

exports.onExecuteCredentialsExchange = async (event, api) => {
  console.log(
    "Client Credentials Exchange - Client:",
    event.client.name,
    event.client.client_id,
    "Audience:",
    event.request.audience,
    "Scope:",
    event.request.scope,
  );

  // Service accounts are identified via client metadata set during bootstrap
  const serviceAccountUserId = event.client.metadata?.service_account_user_id;
  const isServiceAccount = event.client.metadata?.is_service_account === "true";

  if (!isServiceAccount || !serviceAccountUserId) {
    console.log("Not a service account, skipping enrichment");
    return;
  }

  console.log("Starting enrichment for service account:", serviceAccountUserId);

  // Management API client is needed to look up the underlying service-account user
  const ManagementClient = require("auth0").ManagementClient;
  const management = new ManagementClient({
    domain: event.secrets.domain,
    clientId: event.secrets.clientId,
    clientSecret: event.secrets.clientSecret,
    scope: "read:users read:users_app_metadata",
  });

  try {
    // Fetch the service-account user record so we can read its metadata
    const user = await management.getUser({ id: serviceAccountUserId });

    if (!user) {
      console.error("Service account user not found:", serviceAccountUserId);
      return;
    }

    // Note: is_service_account lives on user_metadata; roles & org binding live on app_metadata
    const userMetadata = user.user_metadata || {};
    const appMetadata = user.app_metadata || {};
    const isServiceAccountUser = userMetadata.is_service_account === true;

    if (!isServiceAccountUser) {
      console.error(
        "User is not marked as service account:",
        serviceAccountUserId,
      );
      return;
    }

    const namespace = "https://governance.eqtylab.io/";

    // Identity claims
    api.accessToken.setCustomClaim(namespace + "user_id", user.user_id);
    api.accessToken.setCustomClaim(namespace + "auth0_user_id", user.user_id);
    api.accessToken.setCustomClaim(namespace + "email", user.email);
    api.accessToken.setCustomClaim(
      namespace + "name",
      user.name || "Service Account",
    );

    // Service-account marker and service descriptors (from client metadata)
    api.accessToken.setCustomClaim(namespace + "is_service_account", true);
    api.accessToken.setCustomClaim(
      namespace + "service_name",
      event.client.metadata?.service_name || "unknown",
    );
    api.accessToken.setCustomClaim(
      namespace + "service_type",
      event.client.metadata?.service_type || "unknown",
    );

    // governance-worker is platform-wide; other service accounts are org-scoped
    if (event.client.metadata?.service_name === "governance-worker") {
      api.accessToken.setCustomClaim(namespace + "platform_access", true);
      api.accessToken.setCustomClaim(namespace + "organizations", ["*"]);
      api.accessToken.setCustomClaim(namespace + "roles", [
        "platform:service_account",
        "governance:declarations:create",
        "integrity:statements:create",
      ]);
    } else {
      const organizationId = appMetadata.organization_id;
      if (organizationId) {
        api.accessToken.setCustomClaim(
          namespace + "organization_id",
          organizationId,
        );
        api.accessToken.setCustomClaim(namespace + "organizations", [
          organizationId,
        ]);
      }

      const roles = appMetadata.roles || ["service_account"];
      api.accessToken.setCustomClaim(namespace + "roles", roles);
    }

    // DID key claims
    if (appMetadata.did_key_id) {
      api.accessToken.setCustomClaim(
        namespace + "did_key_id",
        appMetadata.did_key_id,
      );
      api.accessToken.setCustomClaim(
        namespace + "did_key_name",
        appMetadata.did_key_name || appMetadata.did_key_id,
      );
    }

    // Audit timestamp + override sub for downstream DID key lookup
    api.accessToken.setCustomClaim(namespace + "created_at", user.created_at);
    api.accessToken.setCustomClaim("sub", user.user_id);

    console.log(
      "Token enrichment completed for service account:",
      serviceAccountUserId,
    );
  } catch (error) {
    // Don't fail the token request, just log the error
    console.error("Service account enrichment failed:", error);
  }
};
