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
