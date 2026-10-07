import pytest
from fastapi import HTTPException

from services.idempotency import get_existing, validate_transaction_replay


class _Result:
    def __init__(self, data):
        self.data = data


class _Query:
    def __init__(self, row):
        self.row = row
        self.filters = {}
        self.selected = None

    def select(self, fields):
        self.selected = fields
        return self

    def eq(self, field, value):
        self.filters[field] = value
        return self

    def execute(self):
        if not self.row or any(self.row.get(key) != value for key, value in self.filters.items()):
            return _Result([])
        return _Result([self.row])


class _Supabase:
    def __init__(self, row):
        self.row = row

    def table(self, _name):
        return _Query(self.row)


def _reservation(status="completed", **overrides):
    return {
        "idempotency_key": "key-1",
        "user_id": "user-1",
        "operation": "BURN",
        "request_hash": "payload-hash",
        "status": status,
        "tx_hash": "signature",
        "resource_id": "transaction-1",
        "quantity": 3.5,
        "distance_meters": None,
        "installation": None,
        "created_at": "2026-10-03T12:00:00+00:00",
        **overrides,
    }


def _get_existing(db, *, user_id="user-1", operation="BURN", payload_hash="payload-hash"):
    return get_existing(
        db,
        key="key-1",
        user_id=user_id,
        operation=operation,
        payload_hash=payload_hash,
    )


def test_get_existing_returns_completed_reservation():
    result = _get_existing(_Supabase(_reservation()))

    assert result is not None
    assert result.tx_hash == "signature"
    assert result.quantity == 3.5


@pytest.mark.parametrize(
    ("kwargs", "message"),
    [
        ({"user_id": "other-user"}, "another operation"),
        ({"operation": "MINT"}, "another operation"),
        ({"payload_hash": "different-hash"}, "different request"),
    ],
)
def test_get_existing_rejects_incompatible_replay(kwargs, message):
    with pytest.raises(HTTPException) as error:
        _get_existing(_Supabase(_reservation()), **kwargs)

    assert error.value.status_code == 409
    assert message in error.value.detail


def test_get_existing_rejects_pending_reservation():
    with pytest.raises(HTTPException) as error:
        _get_existing(_Supabase(_reservation(status="pending")))

    assert error.value.status_code == 409


def test_get_existing_rejects_completed_reservation_without_receipt_fields():
    with pytest.raises(RuntimeError, match="missing result fields"):
        _get_existing(_Supabase(_reservation(tx_hash=None)))


def test_get_existing_returns_none_when_key_has_no_reservation():
    assert _get_existing(_Supabase(None)) is None


def test_transaction_replay_accepts_same_user_operation_and_amount():
    validate_transaction_replay(
        {"user_id": "user-1", "tipo": "BURN", "quantidade": 3.5},
        user_id="user-1",
        operation="BURN",
        quantity=3.5,
    )


@pytest.mark.parametrize(
    ("transaction", "quantity", "message"),
    [
        ({"user_id": "other-user", "tipo": "BURN", "quantidade": 3.5}, 3.5, "another user"),
        ({"user_id": "user-1", "tipo": "MINT", "quantidade": 3.5}, 3.5, "another operation"),
        ({"user_id": "user-1", "tipo": "BURN", "quantidade": 4.0}, 3.5, "different amount"),
    ],
)
def test_transaction_replay_rejects_user_operation_or_amount_mismatch(
    transaction, quantity, message
):
    with pytest.raises(HTTPException) as error:
        validate_transaction_replay(
            transaction,
            user_id="user-1",
            operation="BURN",
            quantity=quantity,
        )

    assert error.value.status_code == 409
    assert message in error.value.detail
