"""
ResgateCreate.instalacao_coelba format validation (Task 1): not exactly 10
digits -> 422, in FastAPI's Pydantic validation-list shape (a list of
per-field errors), distinct from the geofencing single-object 422 shape
covered in test_geofencing.py.
"""

import pytest


@pytest.mark.parametrize(
    "instalacao_coelba",
    [
        "123456789",  # 9 digits - too short
        "12345678901",  # 11 digits - too long
        "abcdefghij",  # 10 chars, not digits
    ],
)
def test_resgate_invalid_instalacao_coelba_format_is_rejected(
    client, auth_headers, idempotency_key, instalacao_coelba
):
    payload = {"quantidade": 1.0, "instalacao_coelba": instalacao_coelba}
    resp = client.post(
        "/resgates",
        json=payload,
        headers={**auth_headers, "Idempotency-Key": idempotency_key("resgate-validacao")},
    )

    assert resp.status_code == 422, resp.text

    detail = resp.json()["detail"]
    assert isinstance(detail, list)
    assert any(err["loc"][-1] == "instalacao_coelba" for err in detail)
