"""Geofencing rejection (SPEC.md 3.2): descarte reported far from the ecoponto's real location."""

from conftest import FAR_LAT, FAR_LON


def test_descarte_far_from_ecoponto_is_rejected(client, auth_headers, idempotency_key, make_descarte_payload):
    payload = make_descarte_payload(latitude=FAR_LAT, longitude=FAR_LON)
    resp = client.post(
        "/descartes",
        json=payload,
        headers={**auth_headers, "Idempotency-Key": idempotency_key("geofencing")},
    )

    assert resp.status_code == 422, resp.text

    # This is the geofencing single-object 422 shape (routers/descartes.py),
    # distinct from the Pydantic validation-list 422 shape covered in
    # test_resgate_validacao.py.
    detail = resp.json()["detail"]
    assert isinstance(detail, dict)
    assert "descarte_id" in detail
    assert detail["distancia_metros"] > detail["tolerancia_metros"]
