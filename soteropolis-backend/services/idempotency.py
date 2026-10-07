"""Atomic idempotency reservations for irreversible blockchain operations."""

import hashlib
import json
from dataclasses import dataclass
from datetime import datetime, timezone

from fastapi import HTTPException, status
from postgrest.exceptions import APIError
from supabase import Client

_UNIQUE_VIOLATION = "23505"


@dataclass(frozen=True)
class Reservation:
    key: str
    request_hash: str
    status: str
    tx_hash: str | None
    resource_id: str | None
    quantity: float | None
    distance_meters: float | None
    installation: str | None
    signed_transaction: str | None
    last_valid_block_height: int | None
    last_error: str | None
    created_at: str | None


def request_hash(payload: object) -> str:
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def get_existing(
    supabase: Client,
    *,
    key: str,
    user_id: str,
    operation: str,
    payload_hash: str,
    allow_pending: bool = False,
) -> Reservation | None:
    result = (
        supabase.table("idempotency_operations")
        .select("*")
        .eq("idempotency_key", key)
        .execute()
    )
    if not result.data:
        return None

    existing = result.data[0]
    if existing["user_id"] != user_id or existing["operation"] != operation:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Idempotency-Key is already used for another operation",
        )
    if existing["request_hash"] != payload_hash:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Idempotency-Key was reused with a different request",
        )
    if existing["status"] == "pending":
        if allow_pending:
            return _to_reservation(existing)
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An operation with this Idempotency-Key is already in progress",
        )
    if existing["status"] == "prepared":
        if allow_pending:
            return _to_reservation(existing)
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Prepared transaction requires recovery with the same Idempotency-Key",
        )
    if existing["status"] == "needs_reconciliation":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Operation requires reconciliation; do not submit a new transaction",
        )
    if existing["status"] == "failed":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This idempotent operation failed and cannot be retried with the same key",
        )
    if existing["status"] != "completed":
        raise RuntimeError(f"Unknown idempotency status: {existing['status']!r}")

    reservation = _to_reservation(existing)
    if not all(
        (
            reservation.tx_hash,
            reservation.resource_id,
            reservation.quantity is not None,
            reservation.created_at,
        )
    ):
        raise RuntimeError("Completed idempotency reservation is missing result fields")
    return reservation


def validate_transaction_replay(
    transaction: dict,
    *,
    user_id: str,
    operation: str,
    quantity: float,
) -> None:
    if transaction.get("user_id") != user_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Idempotency-Key is already used by another user",
        )
    if transaction.get("tipo") != operation:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Idempotency-Key is already associated with another operation",
        )
    stored_quantity = transaction.get("quantidade")
    if not isinstance(stored_quantity, (int, float)) or abs(stored_quantity - quantity) > 1e-9:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Idempotency-Key is already associated with a different amount",
        )


def reserve(
    supabase: Client,
    *,
    key: str,
    user_id: str,
    operation: str,
    payload_hash: str,
) -> Reservation:
    row = {
        "idempotency_key": key,
        "user_id": user_id,
        "operation": operation,
        "request_hash": payload_hash,
        "status": "pending",
    }
    try:
        result = supabase.table("idempotency_operations").insert(row).execute()
        return _to_reservation(result.data[0])
    except APIError as exc:
        if exc.code != _UNIQUE_VIOLATION:
            raise

    existing = get_existing(
        supabase,
        key=key,
        user_id=user_id,
        operation=operation,
        payload_hash=payload_hash,
    )
    if existing is None:
        raise RuntimeError(
            "Idempotency reservation disappeared after a unique-key conflict"
        )
    return existing


def save_prepared(
    supabase: Client,
    *,
    key: str,
    signature: str,
    serialized_transaction: str,
    last_valid_block_height: int,
) -> None:
    result = (
        supabase.table("idempotency_operations")
        .update(
            {
                "status": "prepared",
                "tx_hash": signature,
                "signed_transaction": serialized_transaction,
                "last_valid_block_height": last_valid_block_height,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        .eq("idempotency_key", key)
        .eq("status", "pending")
        .select("idempotency_key")
        .execute()
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Could not persist the prepared transaction; it was not submitted",
        )


def mark_needs_reconciliation(supabase: Client, *, key: str, error: str) -> None:
    result = (
        supabase.table("idempotency_operations")
        .update(
            {
                "status": "needs_reconciliation",
                "last_error": error[:1000],
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        .eq("idempotency_key", key)
        .eq("status", "prepared")
        .select("idempotency_key")
        .execute()
    )
    if not result.data:
        raise RuntimeError(f"Could not mark operation {key!r} for reconciliation")


def mark_failed(supabase: Client, *, key: str, error: str) -> None:
    result = (
        supabase.table("idempotency_operations")
        .update(
            {
                "status": "failed",
                "signed_transaction": None,
                "last_valid_block_height": None,
                "last_error": error[:1000],
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        .eq("idempotency_key", key)
        .eq("status", "prepared")
        .select("idempotency_key")
        .execute()
    )
    if not result.data:
        raise RuntimeError(f"Could not mark operation {key!r} as failed")


def complete(
    supabase: Client,
    *,
    key: str,
    tx_hash: str,
    resource_id: str,
    quantity: float,
    distance_meters: float | None = None,
    installation: str | None = None,
) -> None:
    result = (
        supabase.table("idempotency_operations")
        .update(
            {
                "status": "completed",
                "tx_hash": tx_hash,
                "resource_id": resource_id,
                "quantity": quantity,
                "distance_meters": distance_meters,
                "installation": installation,
                "signed_transaction": None,
                "last_valid_block_height": None,
                "last_error": None,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        .eq("idempotency_key", key)
        .select("idempotency_key")
        .execute()
    )
    if not result.data:
        raise RuntimeError(f"Could not complete missing idempotency reservation {key!r}")


def _to_reservation(row: dict) -> Reservation:
    return Reservation(
        key=row["idempotency_key"],
        request_hash=row["request_hash"],
        status=row["status"],
        tx_hash=row.get("tx_hash"),
        resource_id=row.get("resource_id"),
        quantity=row.get("quantity"),
        distance_meters=row.get("distance_meters"),
        installation=row.get("installation"),
        signed_transaction=row.get("signed_transaction"),
        last_valid_block_height=row.get("last_valid_block_height"),
        last_error=row.get("last_error"),
        created_at=row.get("created_at"),
    )
