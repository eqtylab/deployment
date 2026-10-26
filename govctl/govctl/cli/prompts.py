"""Interactive prompts for govctl CLI."""

from rich.prompt import Prompt

from govctl.core.artifacts import configure_artifacts, uses_custom_registry

from govctl.core.models import (
    PlatformConfig,
    CloudProvider,
    AuthProvider,
    DatabaseMode,
    KeyManagementProvider,
    CLOUD_TO_KEY_MANAGEMENT,
)
from govctl.utils.validate import (
    is_valid_aws_region,
    is_valid_domain,
    is_valid_email,
    is_valid_environment,
    is_valid_gcp_key_ring_id,
    is_valid_gcp_location,
    is_valid_gcp_project_id,
    is_valid_https_url,
    is_valid_keyvault_url,
    is_valid_realm,
    is_valid_registry_host,
    is_valid_uuid,
)
from govctl.utils.output import console

# Environment name rule, shown when validation fails
ENVIRONMENT_FORMAT = (
    "use up to 63 lowercase letters, digits, and hyphens, starting and ending "
    "with a letter or digit (e.g. staging)"
)


def collect_interactive_config(
    cloud: str | None,
    domain: str | None,
    environment: str | None,
    auth: str | None,
    database: str | None = None,
    artifact_source: str = "cloudsmith",
) -> PlatformConfig:
    """Collect configuration interactively."""
    console.print()

    # --- Domain ---
    if domain:
        domain_value = domain
    else:
        while True:
            domain_value = Prompt.ask("[bold]Domain[/bold]").strip()
            if is_valid_domain(domain_value):
                break
            console.print(
                "[red]Invalid domain format. Please enter a valid domain (e.g. guardian.example.com)[/red]"
            )

    # --- Environment ---
    if environment:
        env = environment.lower()
    else:
        while True:
            env = (
                Prompt.ask(
                    "[bold]Environment[/bold]",
                    default="development",
                )
                .strip()
                .lower()
            )
            if is_valid_environment(env):
                break
            console.print(f"[red]Invalid environment name: {ENVIRONMENT_FORMAT}[/red]")

    # --- Database mode ---
    # Default to external for production, bundled otherwise.
    db_default = "external" if env == "production" else "bundled"
    if database:
        database_mode = DatabaseMode(database.lower())
    else:
        console.print()
        console.print("[bold]Database Configuration:[/bold]")
        db_choice = Prompt.ask(
            "  Database Mode (bundled = Bitnami PostgreSQL in-cluster; external = cloud-managed PostgreSQL)",
            choices=["bundled", "external"],
            default=db_default,
        )
        database_mode = DatabaseMode(db_choice)

    # --- Cloud provider ---
    console.print()
    console.print("[bold]Cloud Configuration:[/bold]")
    if cloud:
        cloud_provider = CloudProvider(cloud.lower())
    else:
        cloud_choice = Prompt.ask(
            "  Cloud Provider",
            choices=["aws", "azure", "gcp"],
            default="gcp",
        )
        cloud_provider = CloudProvider(cloud_choice)

    if cloud_provider == CloudProvider.AWS:
        while True:
            aws_region = Prompt.ask(
                "  AWS Region",
                default="us-east-1",
            )
            if is_valid_aws_region(aws_region):
                break
            console.print(
                "[red]Invalid AWS region format. Expected format: us-east-1, us-gov-west-1, etc.[/red]"
            )

    # Create base config
    config = PlatformConfig(
        cloud_provider=cloud_provider,
        domain=domain_value,
        environment=env,
        auth_provider=AuthProvider.KEYCLOAK,  # placeholder, set below
        database_mode=database_mode,
    )

    if cloud_provider == CloudProvider.AWS:
        config.cloud_region = aws_region

        # S3 access mode: static keys (default) or IAM role (IRSA / instance profile)
        s3_iam_choice = Prompt.ask(
            "  AWS S3 access via IAM role (IRSA / instance profile) instead of static access keys?",
            choices=["yes", "no"],
            default="no",
        )
        config.aws_s3_use_iam_role = s3_iam_choice == "yes"
        if config.aws_s3_use_iam_role:
            console.print(
                "  [dim]For IRSA, a service account with an eks.amazonaws.com/role-arn "
                "annotation will be scaffolded (replace YOUR_IAM_ROLE_ARN); drop the "
                "annotation if you use an instance profile. No platform-aws-s3 secret "
                "will be generated. The IAM role covers S3 only: AWS KMS still needs "
                "static access keys in the platform-aws-kms secret.[/dim]"
            )

    # --- Key Management (required for DID keys) ---
    console.print()
    console.print("[bold]Key Management Configuration (for DID keys):[/bold]")
    km_choice = Prompt.ask(
        "  Key Management Provider",
        choices=["aws_kms", "azure_key_vault", "gcp_kms"],
        default=CLOUD_TO_KEY_MANAGEMENT[cloud_provider].value,
    )
    config.key_management_provider = KeyManagementProvider(km_choice)

    if config.key_management_provider == KeyManagementProvider.AWS_KMS:
        while True:
            aws_kms_region = Prompt.ask(
                "  AWS KMS Region",
                default=config.cloud_region or "us-east-1",
            )
            if is_valid_aws_region(aws_kms_region):
                break
            console.print(
                "[red]Invalid AWS region format. Expected format: us-east-1, us-gov-west-1, etc.[/red]"
            )
        config.aws_kms_region = aws_kms_region
        aws_kms_endpoint = Prompt.ask(
            "  AWS KMS Endpoint (optional, for custom endpoints)",
            default="",
        )
        config.aws_kms_endpoint = aws_kms_endpoint
        aws_kms_alias_prefix = Prompt.ask(
            "  AWS KMS Alias Prefix",
            default="alias/eqtylab/did",
        )
        config.aws_kms_alias_prefix = aws_kms_alias_prefix
    elif config.key_management_provider == KeyManagementProvider.AZURE_KEY_VAULT:
        while True:
            keyvault_url = Prompt.ask("  Azure Key Vault URL").strip()
            if is_valid_keyvault_url(keyvault_url):
                break
            console.print(
                "[red]Invalid Key Vault URL. Expected format: https://{vault-name}.vault.azure.net/ "
                "(or a sovereign cloud suffix such as vault.azure.cn)[/red]"
            )
        config.azure_key_vault_url = keyvault_url
        while True:
            kv_tenant_id = Prompt.ask(
                "  Azure Key Vault Tenant ID",
                default="",
            )
            if not kv_tenant_id or is_valid_uuid(kv_tenant_id):
                break
            console.print(
                "[red]Invalid UUID format. Expected format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx[/red]"
            )
        config.azure_tenant_id = kv_tenant_id
    elif config.key_management_provider == KeyManagementProvider.GCP_KMS:
        while True:
            gcp_kms_project_id = Prompt.ask("  GCP Project ID").strip()
            if is_valid_gcp_project_id(gcp_kms_project_id):
                break
            console.print(
                "[red]Invalid GCP project ID. Must be 6-30 lowercase letters, digits, and hyphens, starting with a letter.[/red]"
            )
        config.gcp_kms_project_id = gcp_kms_project_id
        while True:
            gcp_kms_location = Prompt.ask(
                "  GCP KMS Location",
                default="us-east1",
            )
            if is_valid_gcp_location(gcp_kms_location):
                break
            console.print(
                "[red]Invalid GCP location. Expected format: us-east1, europe-west4, us, nam4, global, etc.[/red]"
            )
        config.gcp_kms_location_id = gcp_kms_location
        while True:
            gcp_kms_key_ring = Prompt.ask(
                "  GCP KMS Key Ring ID",
                default="eqtylab-did",
            )
            if is_valid_gcp_key_ring_id(gcp_kms_key_ring):
                break
            console.print(
                "[red]Invalid key ring ID. Use only letters, numbers, hyphens, and underscores.[/red]"
            )
        config.gcp_kms_key_ring_id = gcp_kms_key_ring

    # --- Auth provider ---
    console.print()
    console.print("[bold]Auth Configuration:[/bold]")
    if auth:
        auth_provider = AuthProvider(auth.lower())
    else:
        auth_choice = Prompt.ask(
            "  Auth Provider",
            choices=["auth0", "entra", "keycloak"],
            default="keycloak",
        )
        auth_provider = AuthProvider(auth_choice)
    config.auth_provider = auth_provider

    if auth_provider == AuthProvider.AUTH0:
        while True:
            auth0_domain = Prompt.ask("  Auth0 Domain").strip()
            if is_valid_domain(auth0_domain):
                break
            console.print(
                "[red]Invalid domain format. Expected format: your-tenant.us.auth0.com[/red]"
            )
        config.auth0_domain = auth0_domain
        while True:
            auth0_audience = Prompt.ask(
                "  Auth0 Audience/API Identifier",
                default=config.auth0_api_identifier,
            )
            if is_valid_https_url(auth0_audience):
                break
            console.print(
                "[red]Invalid Auth0 audience. Expected format: https://guardian.example.com[/red]"
            )
        config.auth0_audience = auth0_audience
    elif auth_provider == AuthProvider.ENTRA:
        while True:
            entra_tenant_id = Prompt.ask(
                "  Entra Tenant ID",
                default="",
            )
            if not entra_tenant_id or is_valid_uuid(entra_tenant_id):
                break
            console.print(
                "[red]Invalid UUID format. Expected format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx[/red]"
            )
        config.entra_tenant_id = entra_tenant_id
    elif auth_provider == AuthProvider.KEYCLOAK:
        while True:
            keycloak_url = (
                Prompt.ask(
                    "  Keycloak URL",
                    default=config.keycloak_base_url,
                )
                .strip()
                .rstrip("/")
            )
            if is_valid_https_url(keycloak_url):
                break
            console.print(
                "[red]Invalid URL format. Expected an HTTPS URL (e.g. https://your-domain.com/keycloak)[/red]"
            )
        config.keycloak_url = keycloak_url
        while True:
            keycloak_realm = Prompt.ask(
                "  Keycloak Realm",
                default="guardian",
            )
            if is_valid_realm(keycloak_realm):
                break
            console.print(
                "[red]Invalid realm name. Use only letters, numbers, hyphens, and underscores.[/red]"
            )
        config.keycloak_realm = keycloak_realm

    # --- Image registry ---
    configure_artifacts(config, artifact_source)
    console.print()
    console.print("[bold]Image Registry Configuration:[/bold]")
    while True:
        registry_url = (
            Prompt.ask(
                "  Registry URL",
                default=config.image_registry_url,
            )
            .strip()
            .lower()
        )
        if is_valid_registry_host(registry_url):
            break
        console.print(
            "[red]Invalid registry host. Expected format: ghcr.io, registry.example.com:5000, etc.[/red]"
        )
    config.image_registry_url = registry_url
    if uses_custom_registry(config):
        # A custom credential host alone cannot redirect the chart's image paths.
        while True:
            prefix = Prompt.ask(
                "  Full image repository prefix", default=f"{registry_url}/eqtylab"
            ).strip()
            if (
                prefix.startswith(registry_url + "/")
                and not any(c.isspace() for c in prefix)
                and "://" not in prefix
                and prefix.rstrip("/") != registry_url
            ):
                config.image_repository_prefix = prefix.rstrip("/")
                break
            console.print(
                "[red]Prefix must start with the registry host followed by / "
                "and a repository path.[/red]"
            )
        config.image_registry_username = ""
    elif registry_url == "ghcr.io":
        configure_artifacts(config, "github")
    else:
        configure_artifacts(config, "cloudsmith")
    config.image_registry_username = Prompt.ask(
        "  Registry Username",
        default=config.image_registry_username,
    )
    while True:
        registry_email = Prompt.ask(
            "  Registry Email",
            default="",
        )
        if not registry_email or is_valid_email(registry_email):
            break
        console.print(
            "[red]Invalid email format. Expected format: user@example.com[/red]"
        )
    config.image_registry_email = registry_email

    return config
