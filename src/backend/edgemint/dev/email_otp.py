"""Development email one-time-code challenges for the customer portal BFF.

Production customer sign-in remains Cognito OIDC. These challenges exist only so
local and test sessions can be opened after an email code check.
"""

from __future__ import annotations

import hashlib
import hmac
import re
import secrets
import smtplib
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from email.message import EmailMessage
from uuid import UUID, uuid4

from edgemint.building_blocks.ids import public_id
from edgemint.dev.fixtures import DEV_PRINCIPAL_ID, DEV_WORKSPACE_PRIMARY

DEV_LOGIN_EMAIL = "dev-user@edgemint.local"
DEV_LOGIN_PASSWORD = "edgemint-dev"  # noqa: S105  local fixture only; production uses OIDC
OTP_TTL = timedelta(minutes=5)
MAX_ATTEMPTS = 5
PASSWORD_MAX_ATTEMPTS = 5
MIN_PASSWORD_LENGTH = 8
_PASSWORD_SALT = b"edgemint-local-login"

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_CODE_RE = re.compile(r"^\d{6}$")


def _password_hash(password: str) -> bytes:
    return hashlib.pbkdf2_hmac("sha256", password.encode(), _PASSWORD_SALT, 100_000)


@dataclass(frozen=True, slots=True)
class LocalAccount:
    principal_id: UUID
    workspace_id: UUID
    role: str
    password_hash: bytes


@dataclass(frozen=True, slots=True)
class LoginIdentity:
    principal_id: UUID
    workspace_id: UUID
    role: str


_ACCOUNTS: dict[str, LocalAccount] = {
    DEV_LOGIN_EMAIL: LocalAccount(
        DEV_PRINCIPAL_ID,
        DEV_WORKSPACE_PRIMARY,
        "customer",
        _password_hash(DEV_LOGIN_PASSWORD),
    ),
}


class EmailOtpError(Exception):
    def __init__(self, detail: str, *, status: int = 401, code: str = "AUTH_INVALID_CREDENTIAL") -> None:
        super().__init__(detail)
        self.detail = detail
        self.status = status
        self.code = code


@dataclass(slots=True)
class _Challenge:
    email: str
    code_hash: str
    expires_at: datetime
    attempts: int = 0
    consumed: bool = False


@dataclass(frozen=True, slots=True)
class IssuedChallenge:
    challenge_id: str
    code: str
    expires_in_seconds: int
    email_dispatched: bool


_challenges: dict[str, _Challenge] = {}
_password_failures: dict[str, int] = {}
_registered_principals: set[UUID] = set()
_accounts_hydrated = False


def reset_email_otp_challenges() -> None:
    global _accounts_hydrated
    _challenges.clear()
    _password_failures.clear()
    _registered_principals.clear()
    _accounts_hydrated = False
    for email in [item for item in _ACCOUNTS if item != DEV_LOGIN_EMAIL]:
        del _ACCOUNTS[email]


def normalize_email(value: str) -> str:
    email = value.strip().lower()
    if not email or len(email) > 254 or _EMAIL_RE.fullmatch(email) is None:
        raise EmailOtpError("Enter a valid email address.", status=422)
    return email


def _hash_code(challenge_id: str, code: str) -> str:
    return hmac.new(challenge_id.encode(), code.encode(), hashlib.sha256).hexdigest()


def deliver_otp_email(recipient: str, code: str, *, host: str, port: int) -> None:
    message = EmailMessage()
    message["From"] = "EdgeMint <noreply@edgemint.local>"
    message["To"] = recipient
    message["Subject"] = "Your EdgeMint sign-in code"
    message.set_content(
        f"Your EdgeMint sign-in code is {code}.\nIt expires in 5 minutes.\n"
    )
    with smtplib.SMTP(host, port, timeout=3) as smtp:
        smtp.send_message(message)


def request_email_otp(
    email: str,
    *,
    now: datetime | None = None,
    send: Callable[[str, str], bool] | None = None,
) -> IssuedChallenge:
    normalized = normalize_email(email)
    if normalized not in _ACCOUNTS:
        raise EmailOtpError("This email is not registered.")
    current = now or datetime.now(tz=UTC)
    stale = [challenge_id for challenge_id, row in _challenges.items() if row.email == normalized]
    for challenge_id in stale:
        del _challenges[challenge_id]
    code = f"{secrets.randbelow(1_000_000):06d}"
    challenge_id = public_id("otp")
    _challenges[challenge_id] = _Challenge(
        email=normalized,
        code_hash=_hash_code(challenge_id, code),
        expires_at=current + OTP_TTL,
    )
    dispatched = bool(send(normalized, code)) if send is not None else False
    return IssuedChallenge(
        challenge_id=challenge_id,
        code=code,
        expires_in_seconds=int(OTP_TTL.total_seconds()),
        email_dispatched=dispatched,
    )


def _identity_for(email: str) -> LoginIdentity:
    account = _ACCOUNTS[email]
    return LoginIdentity(account.principal_id, account.workspace_id, account.role)


def verify_email_otp(
    challenge_id: str,
    email: str,
    code: str,
    *,
    now: datetime | None = None,
) -> LoginIdentity:
    normalized = normalize_email(email)
    submitted = code.strip()
    invalid = EmailOtpError("The code is invalid or expired.")
    if _CODE_RE.fullmatch(submitted) is None:
        raise invalid
    row = _challenges.get(challenge_id)
    current = now or datetime.now(tz=UTC)
    if row is None or row.consumed or row.email != normalized or current >= row.expires_at:
        if row is not None and current >= row.expires_at:
            row.consumed = True
        raise invalid
    if row.attempts >= MAX_ATTEMPTS:
        row.consumed = True
        raise invalid
    row.attempts += 1
    if not hmac.compare_digest(_hash_code(challenge_id, submitted), row.code_hash):
        if row.attempts >= MAX_ATTEMPTS:
            row.consumed = True
        raise invalid
    row.consumed = True
    return _identity_for(normalized)


def is_registered_principal(principal_id: UUID) -> bool:
    return principal_id in _registered_principals


def profile_for_principal(principal_id: UUID) -> dict[str, str] | None:
    for email, account in _ACCOUNTS.items():
        if account.principal_id != principal_id or email == DEV_LOGIN_EMAIL:
            continue
        display_name = email.split("@", 1)[0][:200] or "Portal User"
        return {
            "id": str(principal_id),
            "displayName": display_name,
            "email": email,
            "subject": email,
        }
    return None


def register_local_account(email: str, password: str) -> LoginIdentity:
    normalized = normalize_email(email)
    if normalized in _ACCOUNTS:
        raise EmailOtpError("This email is already registered.", status=409)
    if not MIN_PASSWORD_LENGTH <= len(password) <= 128:
        raise EmailOtpError("Use a password of at least 8 characters.", status=422)
    principal_id = uuid4()
    _ACCOUNTS[normalized] = LocalAccount(
        principal_id,
        DEV_WORKSPACE_PRIMARY,
        "customer",
        _password_hash(password),
    )
    _registered_principals.add(principal_id)
    _password_failures.pop(normalized, None)
    return _identity_for(normalized)


def forget_local_account(email: str) -> None:
    normalized = email.strip().lower()
    if normalized == DEV_LOGIN_EMAIL:
        return
    account = _ACCOUNTS.pop(normalized, None)
    if account is not None:
        _registered_principals.discard(account.principal_id)


async def hydrate_local_accounts() -> None:
    global _accounts_hydrated
    if _accounts_hydrated:
        return
    try:
        from sqlalchemy import text

        from edgemint.building_blocks.database import transaction

        async with transaction() as connection:
            await connection.execute(
                text(
                    """
                    CREATE TABLE IF NOT EXISTS public.dev_local_accounts (
                      email varchar(254) PRIMARY KEY,
                      principal_id uuid NOT NULL REFERENCES public.principals(id),
                      workspace_id uuid NOT NULL,
                      password_hash bytea NOT NULL
                    )
                    """
                )
            )
            rows = await connection.execute(
                text(
                    """
                    SELECT email, principal_id, workspace_id, password_hash
                    FROM public.dev_local_accounts
                    """
                )
            )
            for row in rows.mappings():
                email = str(row["email"])
                if email in _ACCOUNTS:
                    continue
                principal_id = row["principal_id"]
                if not isinstance(principal_id, UUID):
                    principal_id = UUID(str(principal_id))
                workspace_id = row["workspace_id"]
                if not isinstance(workspace_id, UUID):
                    workspace_id = UUID(str(workspace_id))
                _ACCOUNTS[email] = LocalAccount(
                    principal_id,
                    workspace_id,
                    "customer",
                    bytes(row["password_hash"]),
                )
                _registered_principals.add(principal_id)
    except Exception:
        return
    _accounts_hydrated = True


async def persist_local_account(identity: LoginIdentity, email: str) -> None:
    from sqlalchemy import text

    from edgemint.building_blocks.database import transaction

    account = _ACCOUNTS[email]
    display_name = email.split("@", 1)[0][:200] or "Portal User"
    async with transaction(workspace_id=identity.workspace_id) as connection:
        await connection.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS public.dev_local_accounts (
                  email varchar(254) PRIMARY KEY,
                  principal_id uuid NOT NULL REFERENCES public.principals(id),
                  workspace_id uuid NOT NULL,
                  password_hash bytea NOT NULL
                )
                """
            )
        )
        await connection.execute(
            text(
                """
                INSERT INTO public.principals (id, subject, principal_type, display_name)
                VALUES (:id, :subject, 'user', :display_name)
                """
            ),
            {
                "id": identity.principal_id,
                "subject": email,
                "display_name": display_name,
            },
        )
        await connection.execute(
            text(
                """
                INSERT INTO public.workspace_members (id, workspace_id, principal_id, role_code)
                VALUES (:id, :workspace_id, :principal_id, 'workspace_admin')
                """
            ),
            {
                "id": uuid4(),
                "workspace_id": identity.workspace_id,
                "principal_id": identity.principal_id,
            },
        )
        await connection.execute(
            text(
                """
                INSERT INTO public.dev_local_accounts (email, principal_id, workspace_id, password_hash)
                VALUES (:email, :principal_id, :workspace_id, :password_hash)
                """
            ),
            {
                "email": email,
                "principal_id": identity.principal_id,
                "workspace_id": identity.workspace_id,
                "password_hash": account.password_hash,
            },
        )


def verify_email_password(email: str, password: str) -> LoginIdentity:
    normalized = normalize_email(email)
    invalid = EmailOtpError("The email or password is incorrect.")
    failures = _password_failures.get(normalized, 0)
    candidate = _password_hash(password)
    account = _ACCOUNTS.get(normalized)
    matches = account is not None and hmac.compare_digest(candidate, account.password_hash)
    if failures >= PASSWORD_MAX_ATTEMPTS or not matches:
        if account is not None:
            _password_failures[normalized] = failures + 1
        raise invalid
    _password_failures[normalized] = 0
    return _identity_for(normalized)
