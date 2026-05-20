/**
 * Auth0 Action: Service Account Token Enrichment
 * Trigger: Client Credentials Exchange
 *
 * This action enriches M2M tokens with service account user information
 * when the governance-worker M2M application requests a token.
 */

exports.onExecuteCredentialsExchange = async (event, api) => {
  console.log(
    "Client Credentials Exchange - Client:",
    event.client.name,
    event.client.client_id,
  );
  console.log("Client metadata:", JSON.stringify(event.client.metadata));
  console.log("Requested audience:", event.request.audience);
  console.log("Requested scope:", event.request.scope);

  // Check if this is a service account M2M application
  // We identify service accounts by checking client metadata
  const serviceAccountUserId = event.client.metadata?.service_account_user_id;
  const isServiceAccount = event.client.metadata?.is_service_account === "true";

  console.log(
    "Service account check - isServiceAccount:",
    isServiceAccount,
    "userId:",
    serviceAccountUserId,
  );

  if (!isServiceAccount || !serviceAccountUserId) {
    // Not a service account, skip enrichment
    console.log("Not a service account, skipping enrichment");
    return;
  }

  console.log("Starting enrichment for service account:", serviceAccountUserId);

  // Initialize Management API client
  const ManagementClient = require("auth0").ManagementClient;
  const management = new ManagementClient({
    domain: event.secrets.domain,
    clientId: event.secrets.clientId,
    clientSecret: event.secrets.clientSecret,
    scope: "read:users read:users_app_metadata",
  });

  try {
    console.log("Initializing Management API client...");
    console.log("Management API domain:", event.secrets.domain);
    console.log("Management API clientId:", event.secrets.clientId);
    console.log(
      "Management API has clientSecret:",
      !!event.secrets.clientSecret,
    );

    // Fetch the service account user
    console.log("Fetching user:", serviceAccountUserId);
    const user = await management.getUser({ id: serviceAccountUserId });

    console.log("User fetch result:", user ? "User found" : "User not found");

    if (!user) {
      console.error("Service account user not found:", serviceAccountUserId);
      return;
    }

    console.log("User details - email:", user.email, "user_id:", user.user_id);
    console.log("User user_metadata:", JSON.stringify(user.user_metadata));
    console.log("User app_metadata:", JSON.stringify(user.app_metadata));

    // Extract service account metadata
    const userMetadata = user.user_metadata || {};
    const appMetadata = user.app_metadata || {};
    const isServiceAccountUser = userMetadata.is_service_account === true;

    console.log("Is service account user check:", isServiceAccountUser);

    if (!isServiceAccountUser) {
      console.error(
        "User is not marked as service account:",
        serviceAccountUserId,
      );
      return;
    }

    // Define namespace for custom claims
    const namespace = "https://governance.eqtylab.io/";
    console.log("Using namespace:", namespace);

    // Add custom claims to the access token
    // User identification
    console.log("Setting user claims...");
    api.accessToken.setCustomClaim(namespace + "user_id", user.user_id);
    api.accessToken.setCustomClaim(namespace + "auth0_user_id", user.user_id);
    api.accessToken.setCustomClaim(namespace + "email", user.email);
    api.accessToken.setCustomClaim(
      namespace + "name",
      user.name || "Service Account",
    );

    // Service account specific claims
    console.log("Setting service account claims...");
    api.accessToken.setCustomClaim(namespace + "is_service_account", true);
    api.accessToken.setCustomClaim(
      namespace + "service_name",
      event.client.metadata?.service_name || "unknown",
    );
    api.accessToken.setCustomClaim(
      namespace + "service_type",
      event.client.metadata?.service_type || "unknown",
    );

    // Platform access for governance-worker
    if (event.client.metadata?.service_name === "governance-worker") {
      api.accessToken.setCustomClaim(namespace + "platform_access", true);
      api.accessToken.setCustomClaim(namespace + "organizations", ["*"]);
      api.accessToken.setCustomClaim(namespace + "roles", [
        "platform:service_account",
        "governance:declarations:create",
        "integrity:statements:create",
      ]);
    } else {
      // For other service accounts, use their specific metadata
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

      // Add roles from user metadata
      const roles = appMetadata.roles || ["service_account"];
      api.accessToken.setCustomClaim(namespace + "roles", roles);
    }

    // DID key information
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

    // Add created_at timestamp
    api.accessToken.setCustomClaim(namespace + "created_at", user.created_at);
    api.accessToken.setCustomClaim("sub", user.user_id);

    console.log("All claims set successfully");
    console.log(
      "Token enrichment completed for service account:",
      serviceAccountUserId,
    );
    console.log("Action execution finished successfully");
  } catch (error) {
    console.error("ERROR in action execution:", error);
    console.error("Error type:", error.constructor.name);
    console.error("Error message:", error.message);
    console.error("Error stack:", error.stack);
    // Don't fail the token request, just log the error
  }

  console.log("Action onExecuteCredentialsExchange completed");
};
