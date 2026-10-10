from __future__ import annotations

import os
from datetime import UTC, datetime, timedelta

import pytest
from edgemint.building_blocks.settings import Settings
from edgemint.dev import email_otp
from edgemint.dev.fixtures import DEV_PRINCIPAL_ID, DEV_WORKSPACE_PRIMARY
from edgemint.services import api_gateway
from fastapi.testclient import TestClient

TEST_SIGNING_SECRET = "x" * 32

pytestmark = pytest.mark.filterwarnings("ignore::jwt.InsecureKeyLengthWarning")


@pytest.fixture(autouse=True)
def _clear_challenges() -> None:
    email_otp.reset_email_otp_challenges()


def test_unknown_email_is_rejected() -> None:
    with pytest.raises(email_otp.EmailOtpError, match="not registered"):
        email_otp.request_email_otp("nobody@example.com")


def test_valid_code_is_single_use_and_dispatches_email() -> None:
    sent: list[tuple[str, str]] = []

    def send(recipient: str, code: str) -> bool:
        sent.append((recipient, code))
        return True

    issued = email_otp.request_email_otp(email_otp.DEV_LOGIN_EMAIL, send=send)
    assert issued.email_dispatched is True
    assert sent == [(email_otp.DEV_LOGIN_EMAIL, issued.code)]
    assert len(issued.code) == 6 and issued.code.isdigit()

    identity = email_otp.verify_email_otp(
        issued.challenge_id,
        email_otp.DEV_LOGIN_EMAIL,
        issued.code,
    )
    assert identity.principal_id == DEV_PRINCIPAL_ID
    assert identity.workspace_id == DEV_WORKSPACE_PRIMARY
    assert identity.role == "customer"

    with pytest.raises(email_otp.EmailOtpError, match="invalid or expired"):
        email_otp.verify_email_otp(issued.challenge_id, email_otp.DEV_LOGIN_EMAIL, issued.code)


def test_wrong_code_does_not_authenticate_and_locks_after_max_attempts() -> None:
    issued = email_otp.request_email_otp(email_otp.DEV_LOGIN_EMAIL)
    for _ in range(email_otp.MAX_ATTEMPTS):
        with pytest.raises(email_otp.EmailOtpError, match="invalid or expired"):
            email_otp.verify_email_otp(issued.challenge_id, email_otp.DEV_LOGIN_EMAIL, "000000")
    with pytest.raises(email_otp.EmailOtpError, match="invalid or expired"):
        email_otp.verify_email_otp(issued.challenge_id, email_otp.DEV_LOGIN_EMAIL, issued.code)


def test_expired_code_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(email_otp, "OTP_TTL", timedelta(seconds=-1))
    issued = email_otp.request_email_otp(
        email_otp.DEV_LOGIN_EMAIL,
        now=datetime(2026, 10, 7, tzinfo=UTC),
    )
    with pytest.raises(email_otp.EmailOtpError, match="invalid or expired"):
        email_otp.verify_email_otp(
            issued.challenge_id,
            email_otp.DEV_LOGIN_EMAIL,
            issued.code,
            now=datetime(2026, 10, 7, tzinfo=UTC),
        )


def test_http_challenge_rejects_a_wrong_code(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("EDGEMINT_OTP_SMTP_HOST", raising=False)
    monkeypatch.setattr(
        api_gateway,
        "settings",
        Settings(
            _env_file=None,
            environment="test",
            jwt_signing_secret=TEST_SIGNING_SECRET,
            database_url=os.environ.get("EDGEMINT_DATABASE_URL"),
        ),
    )
    client = TestClient(api_gateway.app)
    created = client.post(
        "/auth/email-otp/challenges",
        json={"email": email_otp.DEV_LOGIN_EMAIL},
    )
    assert created.status_code == 200, created.text
    body = created.json()
    assert len(body["devCode"]) == 6
    wrong = "000000" if body["devCode"] != "000000" else "111111"
    rejected = client.post(
        "/auth/email-otp/verify",
        json={
            "challengeId": body["challengeId"],
            "email": email_otp.DEV_LOGIN_EMAIL,
            "code": wrong,
        },
    )
    assert rejected.status_code == 401, rejected.text


def test_password_accepts_the_local_account_and_rejects_other_secrets() -> None:
    identity = email_otp.verify_email_password(
        email_otp.DEV_LOGIN_EMAIL,
        email_otp.DEV_LOGIN_PASSWORD,
    )
    assert identity.principal_id == DEV_PRINCIPAL_ID
    assert identity.workspace_id == DEV_WORKSPACE_PRIMARY
    assert identity.role == "customer"
    with pytest.raises(email_otp.EmailOtpError, match="incorrect"):
        email_otp.verify_email_password(email_otp.DEV_LOGIN_EMAIL, "wrong-password")
    with pytest.raises(email_otp.EmailOtpError, match="incorrect"):
        email_otp.verify_email_password("nobody@example.com", email_otp.DEV_LOGIN_PASSWORD)


def test_password_locks_after_repeated_failures() -> None:
    for _ in range(email_otp.PASSWORD_MAX_ATTEMPTS):
        with pytest.raises(email_otp.EmailOtpError, match="incorrect"):
            email_otp.verify_email_password(email_otp.DEV_LOGIN_EMAIL, "wrong-password")
    with pytest.raises(email_otp.EmailOtpError, match="incorrect"):
        email_otp.verify_email_password(email_otp.DEV_LOGIN_EMAIL, email_otp.DEV_LOGIN_PASSWORD)


def test_http_wrong_password_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        api_gateway,
        "settings",
        Settings(
            _env_file=None,
            environment="test",
            jwt_signing_secret=TEST_SIGNING_SECRET,
            database_url=os.environ.get("EDGEMINT_DATABASE_URL"),
        ),
    )
    client = TestClient(api_gateway.app)
    rejected = client.post(
        "/auth/email-password",
        json={"email": email_otp.DEV_LOGIN_EMAIL, "password": "wrong-password"},
    )
    assert rejected.status_code == 401, rejected.text


def test_email_otp_is_unavailable_outside_local_bff(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        api_gateway,
        "settings",
        Settings(
            _env_file=None,
            environment="production",
            jwt_signing_secret=TEST_SIGNING_SECRET,
            database_url=os.environ.get("EDGEMINT_DATABASE_URL"),
        ),
    )
    client = TestClient(api_gateway.app)
    response = client.post(
        "/auth/email-otp/challenges",
        json={"email": email_otp.DEV_LOGIN_EMAIL},
    )
    assert response.status_code == 503
    password = client.post(
        "/auth/email-password",
        json={"email": email_otp.DEV_LOGIN_EMAIL, "password": email_otp.DEV_LOGIN_PASSWORD},
    )
    assert password.status_code == 503
    signup = client.post(
        "/auth/email-signup",
        json={"email": "new-user@example.com", "password": "new-password"},
    )
    assert signup.status_code == 503


def test_new_challenge_invalidates_the_previous_code() -> None:
    first = email_otp.request_email_otp(email_otp.DEV_LOGIN_EMAIL)
    second = email_otp.request_email_otp(email_otp.DEV_LOGIN_EMAIL)
    with pytest.raises(email_otp.EmailOtpError, match="invalid or expired"):
        email_otp.verify_email_otp(first.challenge_id, email_otp.DEV_LOGIN_EMAIL, first.code)
    email_otp.verify_email_otp(second.challenge_id, email_otp.DEV_LOGIN_EMAIL, second.code)


def test_signup_creates_a_password_account_that_can_receive_a_code() -> None:
    identity = email_otp.register_local_account("new-user@example.com", "new-password")
    assert identity.role == "customer"
    assert identity.principal_id != DEV_PRINCIPAL_ID
    assert identity.workspace_id == DEV_WORKSPACE_PRIMARY
    assert email_otp.is_registered_principal(identity.principal_id)
    signed_in = email_otp.verify_email_password("new-user@example.com", "new-password")
    assert signed_in.principal_id == identity.principal_id
    profile = email_otp.profile_for_principal(identity.principal_id)
    assert profile is not None
    assert profile["email"] == "new-user@example.com"
    issued = email_otp.request_email_otp("new-user@example.com")
    verified = email_otp.verify_email_otp(issued.challenge_id, "new-user@example.com", issued.code)
    assert verified.principal_id == identity.principal_id


def test_signup_rejects_a_duplicate_or_short_password() -> None:
    with pytest.raises(email_otp.EmailOtpError, match="already registered") as duplicate:
        email_otp.register_local_account(email_otp.DEV_LOGIN_EMAIL, "another-password")
    assert duplicate.value.status == 409
    with pytest.raises(email_otp.EmailOtpError, match="at least 8") as short:
        email_otp.register_local_account("short@example.com", "short")
    assert short.value.status == 422


def test_http_signup_opens_a_session_without_touching_the_database(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        api_gateway,
        "settings",
        Settings(
            _env_file=None,
            environment="test",
            jwt_signing_secret=TEST_SIGNING_SECRET,
            database_url=os.environ.get("EDGEMINT_DATABASE_URL"),
        ),
    )

    async def hydrate() -> None:
        return None

    async def persist(identity: email_otp.LoginIdentity, email: str) -> None:
        assert email == "new-user@example.com"
        assert identity.workspace_id == DEV_WORKSPACE_PRIMARY

    async def issue(response, **kwargs):  # noqa: ARG001
        return api_gateway.SessionResponse(
            sessionPublicId="ses_signup",
            workspaceId=kwargs["workspace_id"],
            authorizationGeneration=1,
            expiresAt=datetime(2026, 12, 31, tzinfo=UTC),
            role=kwargs["role"],
        )

    monkeypatch.setattr(email_otp, "hydrate_local_accounts", hydrate)
    monkeypatch.setattr(email_otp, "persist_local_account", persist)
    monkeypatch.setattr(api_gateway, "_issue_browser_session", issue)
    client = TestClient(api_gateway.app)
    created = client.post(
        "/auth/email-signup",
        json={"email": "new-user@example.com", "password": "new-password"},
    )
    assert created.status_code == 201, created.text
    assert created.json()["role"] == "customer"
    rejected = client.post(
        "/auth/email-signup",
        json={"email": "new-user@example.com", "password": "new-password"},
    )
    assert rejected.status_code == 409, rejected.text
