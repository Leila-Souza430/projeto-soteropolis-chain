import os

os.environ.update(
    {
        "SUPABASE_URL": "http://127.0.0.1:54321",
        "SUPABASE_SERVICE_ROLE_KEY": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.fake",
        "SUPABASE_ANON_KEY": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiJ9.fake",
        "TOKEN_RATE_PER_KG": "10",
        "TOKEN_FIXED_AMOUNT": "10",
    }
)

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from models.schemas import DescarteCreate, ResgateCreate
from routers.descartes import create_descarte
from routers.resgates import create_resgate
from services.blockchain import (
    BlockchainNeedsReconciliation,
    BlockchainOutcomeUnknown,
    BlockchainTransactionFailed,
    PreparedTransaction,
)
from services.idempotency import request_hash


@pytest.mark.parametrize("quantity", [float("nan"), float("inf"), float("-inf")])
def test_resgate_schema_rejects_non_finite_amounts(quantity):
    with pytest.raises(ValidationError):
        ResgateCreate(quantidade=quantity, instalacao_coelba="1234567890")


class _Result:
    def __init__(self, data):
        self.data = data


class _Query:
    def __init__(self, rows, database=None):
        self.rows = rows
        self.database = database
        self.filters = {}
        self.update_values = None
        self.insert_value = None

    def select(self, _fields):
        return self

    def update(self, values):
        self.update_values = values
        return self

    def insert(self, value):
        self.insert_value = value
        return self

    def eq(self, field, value):
        self.filters[field] = value
        return self

    def execute(self):
        if self.insert_value is not None:
            self.insert_value.setdefault("id", "2c1c8ae7-2f58-4a0e-8580-c1fd27cd993b")
            self.insert_value.setdefault("created_at", "2026-10-03T12:00:00+00:00")
            self.rows.append(self.insert_value)
            return _Result([self.insert_value])

        matches = [
            row for row in self.rows
            if all(row.get(key) == value for key, value in self.filters.items())
        ]
        if self.update_values is not None:
            for row in matches:
                row.update(self.update_values)
        if self.database is not None and self.database.on_query:
            self.database.on_query(self, matches)
        return _Result(matches)


class _Supabase:
    def __init__(self, *, reservations=None, transactions=None, users=None):
        self.tables = {
            "idempotency_operations": reservations or [],
            "transacoes_tokens": transactions or [],
            "users": users or [],
            "ecopontos": [],
            "descartes": [],
        }
        self.on_query = None

    def table(self, name):
        return _Query(self.tables.get(name, []), self)


class _Blockchain:
    def __init__(self):
        self.burn_calls = 0
        self.mint_calls = 0
        self.prepared_calls = 0
        self.submit_calls = 0
        self.db = None
        self.submit_error = None
        self.mint_error = None

    def burn_tokens(self, *_args):
        self.burn_calls += 1
        raise AssertionError("replay must not reach blockchain")

    def mint_tokens(self, *_args):
        self.mint_calls += 1
        if self.db is not None:
            descarte = self.db.tables["descartes"][-1]
            assert descarte["status"] == "Pendente"
        if self.mint_error:
            raise self.mint_error
        return "mint-signature"

    def prepare_burn_transaction(self, wallet_address, quantity, key):
        self.prepared_calls += 1
        return PreparedTransaction("signature-1", "c2lnbmVk", 1234)

    def submit_prepared_transaction(self, prepared):
        self.submit_calls += 1
        assert prepared.signature == "signature-1"
        assert self.db.tables["idempotency_operations"][0]["status"] == "prepared"
        assert self.db.tables["idempotency_operations"][0]["signed_transaction"] == "c2lnbmVk"
        if self.submit_error:
            raise self.submit_error
        return prepared.signature


def _completed_reservation(*, operation, payload_hash, quantity=3.5, **overrides):
    return {
        "idempotency_key": "key-1",
        "user_id": "user-1",
        "operation": operation,
        "request_hash": payload_hash,
        "status": "completed",
        "tx_hash": "signature",
        "resource_id": "2c1c8ae7-2f58-4a0e-8580-c1fd27cd993b",
        "quantity": quantity,
        "distance_meters": 12.0,
        "installation": "1234567890",
        "created_at": "2026-10-03T12:00:00+00:00",
        **overrides,
    }


def test_resgate_completed_replay_checks_payload_and_never_burns_again():
    payload = ResgateCreate(quantidade=3.5, instalacao_coelba="1234567890")
    db = _Supabase(
        reservations=[
            _completed_reservation(
                operation="BURN",
                payload_hash=request_hash(payload.model_dump(mode="json")),
            )
        ]
    )
    blockchain = _Blockchain()

    result = create_resgate(payload, "key-1", "user-1", db, blockchain)

    assert result.tx_hash == "signature"
    assert result.quantidade == 3.5
    assert blockchain.burn_calls == 0


def test_resgate_replay_rejects_reused_key_with_different_payload():
    payload = ResgateCreate(quantidade=4.0, instalacao_coelba="1234567890")
    db = _Supabase(
        reservations=[
            _completed_reservation(
                operation="BURN",
                payload_hash="hash-of-the-original-request",
            )
        ]
    )
    blockchain = _Blockchain()

    with pytest.raises(HTTPException) as error:
        create_resgate(payload, "key-1", "user-1", db, blockchain)

    assert error.value.status_code == 409
    assert blockchain.burn_calls == 0


def test_resgate_recovers_pending_reservation_from_recorded_burn():
    payload = ResgateCreate(quantidade=3.5, instalacao_coelba="1234567890")
    reservation = _completed_reservation(
        operation="BURN",
        payload_hash=request_hash(payload.model_dump(mode="json")),
        status="pending",
        tx_hash=None,
        resource_id=None,
        created_at="2026-10-03T12:00:00+00:00",
    )
    transaction = {
        "id": "2c1c8ae7-2f58-4a0e-8580-c1fd27cd993b",
        "idempotency_key": "key-1",
        "user_id": "user-1",
        "tipo": "BURN",
        "quantidade": 3.5,
        "tx_hash": "confirmed-signature",
        "created_at": "2026-10-03T12:01:00+00:00",
    }
    db = _Supabase(reservations=[reservation], transactions=[transaction])
    blockchain = _Blockchain()

    result = create_resgate(payload, "key-1", "user-1", db, blockchain)

    assert result.tx_hash == "confirmed-signature"
    assert reservation["status"] == "completed"
    assert reservation["tx_hash"] == "confirmed-signature"
    assert blockchain.burn_calls == 0


def test_resgate_does_not_retry_pending_reservation_without_recorded_burn():
    payload = ResgateCreate(quantidade=3.5, instalacao_coelba="1234567890")
    reservation = _completed_reservation(
        operation="BURN",
        payload_hash=request_hash(payload.model_dump(mode="json")),
        status="pending",
        tx_hash=None,
        resource_id=None,
    )
    db = _Supabase(reservations=[reservation])
    blockchain = _Blockchain()

    with pytest.raises(HTTPException) as error:
        create_resgate(payload, "key-1", "user-1", db, blockchain)

    assert error.value.status_code == 409
    assert "outcome is unresolved" in error.value.detail
    assert blockchain.burn_calls == 0


def _fresh_burn_setup():
    payload = ResgateCreate(quantidade=3.5, instalacao_coelba="1234567890")
    db = _Supabase(
        transactions=[
            {
                "id": "mint-row",
                "user_id": "user-1",
                "tipo": "MINT",
                "quantidade": 10.0,
                "tx_hash": "mint-signature",
                "idempotency_key": "mint-key",
            }
        ],
        users=[
            {
                "id": "user-1",
                "wallet_address": "wallet-1",
                "instalacao_coelba": "1234567890",
            }
        ],
    )
    blockchain = _Blockchain()
    blockchain.db = db
    return payload, db, blockchain


def test_new_burn_persists_signed_transaction_before_submission_and_completes():
    payload, db, blockchain = _fresh_burn_setup()

    result = create_resgate(payload, "key-1", "user-1", db, blockchain)

    assert result.tx_hash == "signature-1"
    assert blockchain.prepared_calls == 1
    assert blockchain.submit_calls == 1
    assert len(db.tables["transacoes_tokens"]) == 2
    reservation = db.tables["idempotency_operations"][0]
    assert reservation["status"] == "completed"
    assert reservation["signed_transaction"] is None


def test_prepared_burn_retry_submits_same_persisted_transaction():
    payload = ResgateCreate(quantidade=3.5, instalacao_coelba="1234567890")
    reservation = _completed_reservation(
        operation="BURN",
        payload_hash=request_hash(payload.model_dump(mode="json")),
        status="prepared",
        tx_hash="signature-1",
        resource_id=None,
        signed_transaction="c2lnbmVk",
        last_valid_block_height=1234,
    )
    db = _Supabase(reservations=[reservation])
    blockchain = _Blockchain()
    blockchain.db = db

    result = create_resgate(payload, "key-1", "user-1", db, blockchain)

    assert result.tx_hash == "signature-1"
    assert blockchain.prepared_calls == 0
    assert blockchain.submit_calls == 1
    assert db.tables["idempotency_operations"][0]["status"] == "completed"


def test_unknown_burn_outcome_keeps_prepared_transaction_for_same_key_retry():
    payload, db, blockchain = _fresh_burn_setup()
    blockchain.submit_error = BlockchainOutcomeUnknown("RPC timeout")

    with pytest.raises(HTTPException) as error:
        create_resgate(payload, "key-1", "user-1", db, blockchain)

    assert error.value.status_code == 503
    assert db.tables["idempotency_operations"][0]["status"] == "prepared"
    assert db.tables["idempotency_operations"][0]["signed_transaction"] == "c2lnbmVk"
    assert blockchain.prepared_calls == 1
    assert blockchain.submit_calls == 1

    blockchain.submit_error = None
    result = create_resgate(payload, "key-1", "user-1", db, blockchain)

    assert result.tx_hash == "signature-1"
    assert blockchain.prepared_calls == 1
    assert blockchain.submit_calls == 2
    assert db.tables["idempotency_operations"][0]["status"] == "completed"


def test_expired_unknown_burn_is_blocked_for_manual_reconciliation():
    payload, db, blockchain = _fresh_burn_setup()
    blockchain.submit_error = BlockchainNeedsReconciliation("expired and unknown")

    with pytest.raises(HTTPException) as error:
        create_resgate(payload, "key-1", "user-1", db, blockchain)

    assert error.value.status_code == 409
    assert "requires reconciliation" in error.value.detail
    assert db.tables["idempotency_operations"][0]["status"] == "needs_reconciliation"
    assert blockchain.submit_calls == 1


def test_definitively_failed_burn_is_recorded_as_failed_and_cannot_be_retried():
    payload, db, blockchain = _fresh_burn_setup()
    blockchain.submit_error = BlockchainTransactionFailed("program rejected burn")

    with pytest.raises(HTTPException) as error:
        create_resgate(payload, "key-1", "user-1", db, blockchain)

    assert error.value.status_code == 422
    reservation = db.tables["idempotency_operations"][0]
    assert reservation["status"] == "failed"
    assert reservation["signed_transaction"] is None
    assert reservation["last_error"] == "program rejected burn"
    assert blockchain.submit_calls == 1


def test_resgate_legacy_replay_rejects_mint_transaction():
    payload = ResgateCreate(quantidade=3.5, instalacao_coelba="1234567890")
    db = _Supabase(
        transactions=[
            {
                "idempotency_key": "key-1",
                "user_id": "user-1",
                "tipo": "MINT",
                "quantidade": 3.5,
            }
        ]
    )
    blockchain = _Blockchain()

    with pytest.raises(HTTPException) as error:
        create_resgate(payload, "key-1", "user-1", db, blockchain)

    assert error.value.status_code == 409
    assert blockchain.burn_calls == 0


def test_descarte_completed_replay_checks_payload_and_never_mints_again():
    payload = DescarteCreate(
        ecoponto_id="1d35c8b5-d186-41ad-b753-266e81e90b4b",
        latitude=-13.01,
        longitude=-38.53,
        tipo_residuo="plastico",
        peso_estimado=0.35,
        foto_url="https://example.com/image.jpg",
    )
    db = _Supabase(
        reservations=[
            _completed_reservation(
                operation="MINT",
                payload_hash=request_hash(payload.model_dump(mode="json")),
                quantity=3.5,
            )
        ]
    )
    blockchain = _Blockchain()

    result = create_descarte(payload, "key-1", "user-1", db, blockchain)

    assert result.tx_hash == "signature"
    assert result.quantidade_tokens == 3.5
    assert blockchain.mint_calls == 0


def test_descarte_legacy_replay_rejects_burn_transaction():
    payload = DescarteCreate(
        ecoponto_id="1d35c8b5-d186-41ad-b753-266e81e90b4b",
        latitude=-13.01,
        longitude=-38.53,
        tipo_residuo="plastico",
        peso_estimado=0.35,
        foto_url="https://example.com/image.jpg",
    )
    db = _Supabase(
        transactions=[
            {
                "idempotency_key": "key-1",
                "user_id": "user-1",
                "tipo": "BURN",
                "quantidade": 3.5,
            }
        ]
    )
    blockchain = _Blockchain()

    with pytest.raises(HTTPException) as error:
        create_descarte(payload, "key-1", "user-1", db, blockchain)

    assert error.value.status_code == 409
    assert blockchain.mint_calls == 0


def _fresh_descarte_setup():
    payload = DescarteCreate(
        ecoponto_id="1d35c8b5-d186-41ad-b753-266e81e90b4b",
        latitude=-13.01,
        longitude=-38.53,
        tipo_residuo="plastico",
        peso_estimado=0.35,
        foto_url="https://example.com/image.jpg",
    )
    db = _Supabase(
        users=[{"id": "user-1", "wallet_address": "wallet-1"}],
    )
    db.tables["ecopontos"].append(
        {
            "id": "1d35c8b5-d186-41ad-b753-266e81e90b4b",
            "nome": "Ecoponto teste",
            "latitude": -13.01,
            "longitude": -38.53,
            "ativo": True,
        }
    )
    blockchain = _Blockchain()
    blockchain.db = db
    return payload, db, blockchain


def test_descarte_stays_pending_when_mint_fails():
    payload, db, blockchain = _fresh_descarte_setup()
    blockchain.mint_error = RuntimeError("simulated mint failure")

    with pytest.raises(RuntimeError, match="simulated mint failure"):
        create_descarte(payload, "key-1", "user-1", db, blockchain)

    assert db.tables["descartes"][0]["status"] == "Pendente"
    assert not db.tables["transacoes_tokens"]
    assert db.tables["idempotency_operations"][0]["status"] == "pending"


def test_descarte_is_validated_only_after_mint_and_transaction_record():
    payload, db, blockchain = _fresh_descarte_setup()

    result = create_descarte(payload, "key-1", "user-1", db, blockchain)

    assert result.status.value == "Validado"
    assert db.tables["descartes"][0]["status"] == "Validado"
    assert db.tables["transacoes_tokens"][0]["tx_hash"] == "mint-signature"
    assert db.tables["idempotency_operations"][0]["status"] == "completed"
