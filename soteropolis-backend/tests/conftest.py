"""
Shared fixtures for the Fase 5 E2E suite.

BLOCKCHAIN_MODE is forced to "solana" below, before anything imports
config/main, so every test in this suite exercises the real
devnet-integrated SolanaBlockchainService - never MockBlockchainService -
without touching the checked-in .env (which stays "mock" for normal
`uvicorn --reload` dev). Everything else (SOLANA_RPC_URL, program id, mint
address, authority keypair path) is still sourced from that .env file:
pydantic-settings only overrides a key here if it's actually present in
os.environ, and BLOCKCHAIN_MODE is the only one set here.
"""

import os
import uuid

os.environ["BLOCKCHAIN_MODE"] = "solana"

import httpx
import pytest
from starlette.testclient import TestClient

from config import settings
from main import app
from services.blockchain import BlockchainError, SolanaBlockchainService

TEST_USER_EMAIL = "teste@soteropolis.com"
TEST_USER_PASSWORD = "Teste123!"

# Known-good fixtures, confirmed live in Supabase before writing this suite:
# ecoponto "Ecoponto Teste - Barra" at exactly this lat/lon.
ECOPONTO_ID = "1d35c8b5-d186-41ad-b753-266e81e90b4b"
ECOPONTO_LAT = -13.01
ECOPONTO_LON = -38.53

# Far enough from the ecoponto above to clear the 50m geofence tolerance.
FAR_LAT = -12.9714
FAR_LON = -38.5014

# A syntactically valid mock Coelba installation number (exactly 10 digits).
VALID_INSTALACAO_COELBA = "1234567890"


@pytest.fixture(scope="session")
def client() -> TestClient:
    """In-process ASGI client - calls the `app` object directly, no separate
    uvicorn process needed."""
    return TestClient(app)


@pytest.fixture(scope="session")
def supabase_admin():
    """Direct service_role Supabase client (same pattern as database.py) for
    asserting on raw DB state - e.g. that idempotent replays never insert a
    second transacoes_tokens row."""
    from supabase import create_client

    return create_client(settings.supabase_url, settings.supabase_service_role_key)


@pytest.fixture(scope="session")
def _login_response() -> dict:
    """Real Supabase Auth login - the same POST {SUPABASE_URL}/auth/v1/token
    ?grant_type=password mechanism used throughout this project's manual
    testing, not a mock/bypass."""
    response = httpx.post(
        f"{settings.supabase_url}/auth/v1/token?grant_type=password",
        headers={"apikey": settings.supabase_anon_key, "Content-Type": "application/json"},
        json={"email": TEST_USER_EMAIL, "password": TEST_USER_PASSWORD},
        timeout=30.0,
    )
    response.raise_for_status()
    return response.json()


@pytest.fixture(scope="session")
def auth_token(_login_response: dict) -> str:
    return _login_response["access_token"]


@pytest.fixture(scope="session")
def test_user_id(_login_response: dict) -> str:
    return _login_response["user"]["id"]


@pytest.fixture(scope="session")
def auth_headers(auth_token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {auth_token}"}


@pytest.fixture(scope="session", autouse=True)
def _ensure_valid_wallet(supabase_admin, test_user_id: str) -> None:
    """
    Verify-only guard on the shared test user's wallet_address, run before
    any test in this suite.

    Used to self-heal a known-bad wallet_address by writing a fresh keypair
    straight into the real `users` row. Flagged as an unwanted side effect
    - running the suite must never silently mutate shared, production-ish
    data - so this now only verifies and fails loudly instead. This
    fixture makes NO database write, in either branch below.

    Reuses SolanaBlockchainService._validate_citizen_pubkey (Check A) - the
    exact same on-curve check mint_tokens/burn_tokens run against this
    address - instead of duplicating that validation logic here.
    """
    result = supabase_admin.table("users").select("wallet_address").eq("id", test_user_id).execute()
    current = result.data[0]["wallet_address"] if result.data else None

    if not current:
        pytest.fail(
            f"Test user {test_user_id} has no wallet_address set in public.users. "
            "Fix manually: generate a fresh solders.keypair.Keypair() and write its "
            "pubkey to public.users.wallet_address for this user via the "
            "service_role client, then re-run the suite."
        )

    try:
        SolanaBlockchainService._validate_citizen_pubkey(current)
    except BlockchainError as exc:
        pytest.fail(
            f"Test user {test_user_id}'s wallet_address {current!r} is broken: {exc}. "
            "It is off-curve (or malformed), so every mint_tokens/burn_tokens call in "
            "this suite would be rejected by Check A. This fixture no longer "
            "self-heals it automatically - fix it manually the same way it was fixed "
            "last time: generate a fresh solders.keypair.Keypair(), then update "
            "public.users.wallet_address for this user to that keypair's pubkey via "
            "the service_role client, then re-run the suite."
        )


@pytest.fixture
def idempotency_key():
    """Factory for e2e-{scenario}-{uuid4} keys (confirmed convention) - keeps
    test-generated rows identifiable and non-colliding with prior manual
    test rows (teste-abc-001, etc.) or other test runs."""

    def _make(scenario: str) -> str:
        return f"e2e-{scenario}-{uuid.uuid4()}"

    return _make


@pytest.fixture
def make_descarte_payload():
    """Factory for a valid /descartes body targeting the known test
    ecoponto. `latitude`/`longitude` default to the ecoponto's own
    coordinates (well inside the geofence); override to test rejection."""

    def _make(
        *,
        latitude: float = ECOPONTO_LAT,
        longitude: float = ECOPONTO_LON,
        peso_estimado: float | None = 1.0,
        foto_url: str = "https://example.com/foto-e2e.jpg",
        tipo_residuo: str = "plastico",
    ) -> dict:
        return {
            "ecoponto_id": ECOPONTO_ID,
            "latitude": latitude,
            "longitude": longitude,
            "tipo_residuo": tipo_residuo,
            "peso_estimado": peso_estimado,
            "foto_url": foto_url,
        }

    return _make
