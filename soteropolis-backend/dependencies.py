"""Auth dependency: delegates Supabase Auth JWT validation to Supabase itself."""

import httpx
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from config import settings

# auto_error=False so a missing header is handled below and reported as 401,
# instead of HTTPBearer's default 403.
_bearer_scheme = HTTPBearer(auto_error=False)

_VALIDATE_TIMEOUT_SECONDS = 10.0


async def get_current_user_id(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
) -> str:
    """
    Verify the Supabase Auth JWT from `Authorization: Bearer <token>` and
    return the caller's user id.

    This is the only source of truth for "who is calling" - routes must never
    trust a user_id supplied in a request body or query string.
    """
    if credentials is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")

    # Delegate validation to Supabase (GET /auth/v1/user) instead of decoding
    # locally: a shared HS256 secret doesn't exist for projects using
    # Supabase's newer asymmetric JWT signing keys, so this avoids depending
    # on one.
    try:
        async with httpx.AsyncClient(timeout=_VALIDATE_TIMEOUT_SECONDS) as client:
            response = await client.get(
                f"{settings.supabase_url}/auth/v1/user",
                headers={
                    "Authorization": f"Bearer {credentials.credentials}",
                    "apikey": settings.supabase_anon_key,
                },
            )
    except httpx.HTTPError as exc:
        # Network/timeout errors are treated the same as an invalid token -
        # no separate 503 path for this MVP.
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token") from exc

    if response.status_code != 200:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    user_id = response.json().get("id")
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    return user_id
