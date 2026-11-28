from __future__ import annotations

import re
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.settings import Settings
from edgemint.dev.email_otp import DEV_LOGIN_EMAIL
from edgemint.dev.fixtures import DEV_PRINCIPAL_ID
from edgemint.operations.policy import ROLE_PERMISSIONS

DEFAULT_ADMIN_ROLE = "operator.approver"
_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

_ENSURE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS public.operations_admin_emails (
  email varchar(254) PRIMARY KEY,
  role varchar(64) NOT NULL,
  created_by varchar(254) NOT NULL,
  created_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at_utc timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT CK_operations_admin_emails_role CHECK (
    role IN (
      'operator.readonly',
      'operator.standard',
      'operator.approver',
      'operator.break_glass'
    )
  )
)
"""


def normalize_admin_email(value: str) -> str:
    email = value.strip().lower()
    if not email or len(email) > 254 or _EMAIL_RE.fullmatch(email) is None:
        raise ValueError("INVALID_EMAIL")
    return email


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
        roles[normalize_admin_email(email)] = role
    return roles


async def ensure_admin_emails_table(connection: AsyncConnection) -> None:
    await connection.execute(text(_ENSURE_TABLE_SQL))


async def load_managed_admin_roles(connection: AsyncConnection) -> dict[str, str]:
    await ensure_admin_emails_table(connection)
    rows = await connection.execute(
        text("SELECT email, role FROM public.operations_admin_emails ORDER BY email")
    )
    return {str(row.email): str(row.role) for row in rows}


async def resolve_admin_role(
    connection: AsyncConnection,
    settings: Settings,
    email: str | None,
) -> str | None:
    if not email:
        return None
    managed = await load_managed_admin_roles(connection)
    if email in managed:
        return managed[email]
    return admin_roles(settings).get(email)


async def list_admin_entries(
    connection: AsyncConnection,
    settings: Settings,
) -> list[dict[str, Any]]:
    env_roles = admin_roles(settings)
    managed_rows = await _load_managed_rows(connection)
    managed_by_email = {str(row["email"]): row for row in managed_rows}
    items: list[dict[str, Any]] = []
    for email, role in sorted(env_roles.items()):
        managed = managed_by_email.get(email)
        if managed is not None:
            items.append(
                {
                    "email": email,
                    "role": str(managed["role"]),
                    "source": "managed",
                    "editable": True,
                    "overridesEnvironment": True,
                    "createdBy": managed["created_by"],
                    "updatedAt": managed["updated_at_utc"].isoformat()
                    if managed["updated_at_utc"] is not None
                    else None,
                }
            )
        else:
            items.append(
                {
                    "email": email,
                    "role": role,
                    "source": "environment",
                    "editable": False,
                    "overridesEnvironment": False,
                    "createdBy": None,
                    "updatedAt": None,
                }
            )
    for email, row in sorted(managed_by_email.items()):
        if email in env_roles:
            continue
        items.append(
            {
                "email": email,
                "role": str(row["role"]),
                "source": "managed",
                "editable": True,
                "overridesEnvironment": False,
                "createdBy": row["created_by"],
                "updatedAt": row["updated_at_utc"].isoformat()
                if row["updated_at_utc"] is not None
                else None,
            }
        )
    items.sort(key=lambda item: str(item["email"]))
    return items


async def upsert_admin_email(
    connection: AsyncConnection,
    *,
    email: str,
    role: str,
    created_by: str,
) -> dict[str, Any]:
    if role not in ROLE_PERMISSIONS:
        raise ValueError("UNKNOWN_ROLE")
    normalized = normalize_admin_email(email)
    actor = normalize_admin_email(created_by) if "@" in created_by else created_by
    await ensure_admin_emails_table(connection)
    await connection.execute(
        text(
            """
            INSERT INTO public.operations_admin_emails (email, role, created_by)
            VALUES (:email, :role, :created_by)
            ON CONFLICT (email) DO UPDATE
              SET role = EXCLUDED.role,
                  updated_at_utc = CURRENT_TIMESTAMP
            """
        ),
        {"email": normalized, "role": role, "created_by": actor},
    )
    row = (
        await connection.execute(
            text(
                """
                SELECT email, role, created_by, updated_at_utc
                FROM public.operations_admin_emails
                WHERE email = :email
                """
            ),
            {"email": normalized},
        )
    ).mappings().one()
    return {
        "email": str(row["email"]),
        "role": str(row["role"]),
        "source": "managed",
        "editable": True,
        "overridesEnvironment": False,
        "createdBy": row["created_by"],
        "updatedAt": row["updated_at_utc"].isoformat() if row["updated_at_utc"] is not None else None,
    }


async def delete_admin_email(
    connection: AsyncConnection,
    *,
    email: str,
    actor_id: str,
) -> bool:
    normalized = normalize_admin_email(email)
    if normalized == actor_id.strip().lower():
        raise ValueError("CANNOT_REMOVE_SELF")
    await ensure_admin_emails_table(connection)
    result = await connection.execute(
        text("DELETE FROM public.operations_admin_emails WHERE email = :email"),
        {"email": normalized},
    )
    return bool(result.rowcount)


async def _load_managed_rows(connection: AsyncConnection) -> list[dict[str, Any]]:
    await ensure_admin_emails_table(connection)
    rows = await connection.execute(
        text(
            """
            SELECT email, role, created_by, updated_at_utc
            FROM public.operations_admin_emails
            ORDER BY email
            """
        )
    )
    return [dict(row) for row in rows.mappings()]


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
