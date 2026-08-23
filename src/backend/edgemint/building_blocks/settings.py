from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="EDGEMINT_",
        env_file=".env",
        extra="ignore",
        case_sensitive=False,
    )

    environment: Literal["development", "test", "staging", "production"] = "development"
    database_url: str | None = None
    service_name: str = "unknown"
    contract_version: str = "5.0.0"
    jwt_issuer: str | None = None
    jwt_signing_secret: str | None = None
    jwt_audience: str = "edgemint"
    allow_insecure_development_tokens: bool = False
    websocket_heartbeat_seconds: int = 20
    websocket_ack_timeout_seconds: int = 30
    websocket_max_in_flight: int = 256
    file_max_upload_bytes: int = 52_428_800
    file_signed_url_ttl_seconds: int = 900
    file_storage_backend: Literal["memory", "s3"] = "memory"
    s3_bucket: str | None = None
    s3_kms_key_id: str | None = None
    task_admission_max_drafts: int = 256
    worker_challenge_ttl_seconds: int = 300
    worker_session_ttl_seconds: int = 43_200
    worker_heartbeat_interval_seconds: int = 20
    worker_attestation_ttl_hours: int = 24
    worker_consent_policy_version: str = "2026-q3-v1"
    worker_registry_workspace_id: str | None = None
    model_registry_workspace_id: str | None = None
    model_signing_secret: str | None = None
    model_chunk_size_bytes: int = 4_194_304
    model_approved_licenses: str = "Apache-2.0,MIT,BSD-3-Clause"
    lease_credential_encryption_key: str | None = None
    worker_api_public_base_url: str = "http://worker-gateway:8080"

    @model_validator(mode="after")
    def reject_insecure_production_configuration(self) -> Settings:
        if self.environment in {"staging", "production"} and self.allow_insecure_development_tokens:
            raise ValueError("INSECURE_DEVELOPMENT_TOKENS_FORBIDDEN")
        return self

    def require_database_url(self) -> str:
        if not self.database_url:
            raise RuntimeError("EDGEMINT_DATABASE_URL_REQUIRED")
        return self.database_url


@lru_cache
def get_settings() -> Settings:
    return Settings()
