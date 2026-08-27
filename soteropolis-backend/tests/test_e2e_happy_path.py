"""
Full E2E happy path (SPEC.md 3.4 / PLANO_DE_ACAO.md Fase 5):
descarte (GPS + geofencing) -> mint -> resgate (Coelba) -> burn.
"""

import hashlib

from conftest import VALID_INSTALACAO_COELBA


def _is_mock_tx_hash(tx_hash: str, operation: str, idempotency_key: str) -> bool:
    """
    True if `tx_hash` matches MockBlockchainService's deterministic
    sha256("mock:<mint|burn>:<idempotency_key>") shape (see
    services/blockchain.py). A real devnet signature never collides with
    this, so a mismatch proves the real SolanaBlockchainService ran.
    """
    expected_mock_value = hashlib.sha256(f"mock:{operation}:{idempotency_key}".encode()).hexdigest()
    return tx_hash == expected_mock_value


def test_descarte_then_resgate_full_cycle(client, auth_headers, idempotency_key, make_descarte_payload):
    # 1. Descarte within the geofence tolerance for the known test ecoponto.
    descarte_key = idempotency_key("happy-descarte")
    descarte_resp = client.post(
        "/descartes",
        json=make_descarte_payload(),
        headers={**auth_headers, "Idempotency-Key": descarte_key},
    )

    assert descarte_resp.status_code == 201, descarte_resp.text
    descarte_body = descarte_resp.json()
    assert descarte_body["status"] == "Validado"
    assert descarte_body["quantidade_tokens"] > 0

    mint_tx_hash = descarte_body["tx_hash"]
    assert mint_tx_hash
    assert not _is_mock_tx_hash(mint_tx_hash, "mint", descarte_key), (
        f"tx_hash {mint_tx_hash!r} matches the MOCK pattern - real devnet was not hit"
    )

    # 2. Resgate (burn) an amount <= what was just minted, with a valid
    # 10-digit mock Coelba installation number (Task 1).
    resgate_key = idempotency_key("happy-resgate")
    resgate_resp = client.post(
        "/resgates",
        json={"quantidade": descarte_body["quantidade_tokens"], "instalacao_coelba": VALID_INSTALACAO_COELBA},
        headers={**auth_headers, "Idempotency-Key": resgate_key},
    )

    assert resgate_resp.status_code == 201, resgate_resp.text
    resgate_body = resgate_resp.json()
    assert resgate_body["status"] == "Confirmado"
    # Task 1: the "recibo digital" now echoes back the installation number.
    assert resgate_body["instalacao_coelba"] == VALID_INSTALACAO_COELBA

    burn_tx_hash = resgate_body["tx_hash"]
    assert burn_tx_hash
    assert not _is_mock_tx_hash(burn_tx_hash, "burn", resgate_key), (
        f"tx_hash {burn_tx_hash!r} matches the MOCK pattern - real devnet was not hit"
    )

    print(f"\n[happy-path] mint tx_hash: {mint_tx_hash}")
    print(f"[happy-path] burn tx_hash: {burn_tx_hash}")


def test_descarte_over_mint_cap_is_rejected(client, auth_headers, idempotency_key, make_descarte_payload):
    """Task 2 Check B: quantidade_tokens over settings.max_quantidade_tokens_per_descarte is rejected."""
    # peso_estimado=200 * TOKEN_RATE_PER_KG(10) = 2000 GT, comfortably over
    # the 1000.0 default cap.
    payload = make_descarte_payload(peso_estimado=200.0)
    resp = client.post(
        "/descartes",
        json=payload,
        headers={**auth_headers, "Idempotency-Key": idempotency_key("mint-cap")},
    )

    assert resp.status_code == 400, resp.text
