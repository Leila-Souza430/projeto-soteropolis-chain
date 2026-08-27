"""
Insufficient-balance rejection: a /resgates burn for more than the
citizen's current balance must be rejected with a clean 400, never reach
the chain.

The pre-existing balance fluctuates across manual testing and prior test
runs, so rather than trust a stale known-balance figure, this test mints a
small known amount first and then asks to burn far more than that,
guaranteeing the request exceeds the true balance regardless of whatever
it was beforehand - deterministic and independent of prior runs.
"""

from conftest import VALID_INSTALACAO_COELBA


def test_resgate_burn_exceeds_balance_is_rejected(
    client, auth_headers, idempotency_key, make_descarte_payload
):
    descarte_resp = client.post(
        "/descartes",
        json=make_descarte_payload(),
        headers={**auth_headers, "Idempotency-Key": idempotency_key("saldo-mint")},
    )
    assert descarte_resp.status_code == 201, descarte_resp.text
    minted = descarte_resp.json()["quantidade_tokens"]

    # However large the pre-existing balance was, minted + 1,000,000 must
    # exceed the total - there is no burn-side cap (Task 2 scopes the mint
    # cap to /descartes only), so this fails purely on the balance check.
    payload = {"quantidade": minted + 1_000_000.0, "instalacao_coelba": VALID_INSTALACAO_COELBA}
    resp = client.post(
        "/resgates",
        json=payload,
        headers={**auth_headers, "Idempotency-Key": idempotency_key("saldo-burn")},
    )

    assert resp.status_code == 400, resp.text
