from __future__ import annotations

from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.settings import Settings
from edgemint.dev.email_otp import DEV_LOGIN_EMAIL, normalize_email
from edgemint.dev.fixtures import DEV_PRINCIPAL_ID
from edgemint.operations.policy import ROLE_PERMISSIONS

DEFAULT_ADMIN_ROLE = "operator.approver"


def admin_roles(settings: Settings) -> dict[str, str]:
    """Parse ``EDGEMINT_OPERATIONS_ADMIN_EMAILS`` (``email`` or ``email=role``, comma separated)."""
    raw = settings.operations_admin_emails
    if raw is None:
        return {DEV_LOGIN_EMAIL: DEFAULT_ADMIN_ROLE} if settings.environment == "development" else {}
    roles: dict[str, str] = {}
    for entry in raw.split(","):
        email, _, role = entry.strip().partition("=")
        if not email:
            continue
        role = role.strip() or DEFAULT_ADMIN_ROLE
        if role not in ROLE_PERMISSIONS:
            raise ValueError(f"OPERATIONS_ADMIN_ROLE_UNKNOWN:{role}")
        roles[normalize_email(email)] = role
    return roles


async def portal_email_for_principal(connection: AsyncConnection, principal_id: UUID) -> str | None:
    if principal_id == DEV_PRINCIPAL_ID:
        return DEV_LOGIN_EMAIL
    table = (
        await connection.execute(text("SELECT to_regclass('public.dev_local_accounts')"))
    ).scalar_one()
    if table is None:
        return None
    email = (
        await connection.execute(
            text("SELECT email FROM public.dev_local_accounts WHERE principal_id = :principal_id"),
            {"principal_id": principal_id},
        )
    ).scalar_one_or_none()
    return str(email) if email is not None else None
