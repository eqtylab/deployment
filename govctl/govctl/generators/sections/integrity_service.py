"""Integrity service section generator."""

from typing import Any

from govctl.core.models import PlatformConfig, CloudProvider


def generate_integrity_service_section(config: PlatformConfig) -> dict[str, Any]:
    """Generate the integrity-service section of values.yaml."""
    section: dict[str, Any] = {
        "replicaCount": 2,
        "image": {
            "tag": "",
            "pullPolicy": "Always",
        },
    }

    if config.enable_ingress:
        section["ingress"] = {
            "enabled": True,
            "className": "nginx",
            "annotations": {
                "cert-manager.io/issuer": "letsencrypt-prod",
                "nginx.ingress.kubernetes.io/use-regex": "true",
                "nginx.ingress.kubernetes.io/rewrite-target": "/$2",
                "nginx.ingress.kubernetes.io/enable-cors": "true",
                "nginx.ingress.kubernetes.io/proxy-body-size": "0",
            },
            "hosts": [
                {
                    "host": config.domain,
                    "paths": [
                        {
                            "path": "/integrityService(/|$)(.*)",
                            "pathType": "ImplementationSpecific",
                        }
                    ],
                }
            ],
            "tls": [
                {
                    "secretName": f"{config.environment}-tls-secret",
                    "hosts": [config.domain],
                }
            ],
        }

    # Persistence
    section["persistence"] = {"enabled": True}

    # Storage configuration - integrity-service supports aws_s3 and azure_blob
    section["config"] = {}

    if config.cloud_provider == CloudProvider.AWS:
        section["config"]["integrityAppBlobStoreType"] = "aws_s3"
        section["config"]["integrityAppBlobStoreAwsRegion"] = (
            config.cloud_region or "us-east-1"
        )
        section["config"]["integrityAppBlobStoreAwsBucket"] = "YOUR_S3_BUCKET"
        section["config"]["integrityAppBlobStoreAwsFolder"] = "rootstore"
    elif config.cloud_provider == CloudProvider.AZURE:
        section["config"]["integrityAppBlobStoreType"] = "azure_blob"
        section["config"]["integrityAppBlobStoreAccount"] = "YOUR_STORAGE_ACCOUNT"
        section["config"]["integrityAppBlobStoreContainer"] = "rootstore"
    elif config.cloud_provider == CloudProvider.GCP:
        # GCP deployments use Azure blob storage for integrity-service
        section["config"]["integrityAppBlobStoreType"] = "azure_blob"
        section["config"]["integrityAppBlobStoreAccount"] = "YOUR_AZURE_STORAGE_ACCOUNT"
        section["config"]["integrityAppBlobStoreContainer"] = "rootstore"

    return section
