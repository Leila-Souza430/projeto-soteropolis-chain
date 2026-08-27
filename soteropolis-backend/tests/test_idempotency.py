"""
Idempotency-Key replay (SPEC.md 3.3): a resent request must return the
original tx_hash and must never insert a second transacoes_tokens row.
"""

from conftest import VALID_INSTALACAO_COELBA


def _rows_for_idempotency_key(supabase_admin, key: str) -> list[dict]:
    result = supabase_admin.table("transacoes_tokens").select("*").eq("idempotency_key", key).execute()
    return result.data


def test_descarte_replay_returns_same_tx_hash_no_duplicate_row(
    client, auth_headers, idempotency_key, make_descarte_payload, supabase_admin
):
    key = idempotency_key("idempotency-descarte")
    payload = make_descarte_payload()
    headers = {**auth_headers, "Idempotency-Key": key}

    first = client.post("/descartes", json=payload, headers=headers)
    assert first.status_code == 201, first.text

    second = client.post("/descartes", json=payload, headers=headers)
    assert second.status_code == 201, second.text

    assert first.json()["tx_hash"] == second.json()["tx_hash"]

    rows = _rows_for_idempotency_key(supabase_admin, key)
    assert len(rows) == 1, f"expected exactly 1 transacoes_tokens row for {key!r}, found {len(rows)}"


def test_resgate_replay_returns_same_tx_hash_no_duplicate_row(
    client, auth_headers, idempotency_key, make_descarte_payload, supabase_admin
):
    # Mint first so there is balance to burn against.
    descarte_resp = client.post(
        "/descartes",
        json=make_descarte_payload(),
        headers={**auth_headers, "Idempotency-Key": idempotency_key("idempotency-resgate-mint")},
    )
    assert descarte_resp.status_code == 201, descarte_resp.text
    minted = descarte_resp.json()["quantidade_tokens"]

    key = idempotency_key("idempotency-resgate")
    payload = {"quantidade": minted, "instalacao_coelba": VALID_INSTALACAO_COELBA}
    headers = {**auth_headers, "Idempotency-Key": key}

    first = client.post("/resgates", json=payload, headers=headers)
    assert first.status_code == 201, first.text

    second = client.post("/resgates", json=payload, headers=headers)
    assert second.status_code == 201, second.text

    assert first.json()["tx_hash"] == second.json()["tx_hash"]

    rows = _rows_for_idempotency_key(supabase_admin, key)
    assert len(rows) == 1, f"expected exactly 1 transacoes_tokens row for {key!r}, found {len(rows)}"
