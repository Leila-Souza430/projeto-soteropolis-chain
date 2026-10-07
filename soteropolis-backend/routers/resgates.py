"""Resgates (Green Token redemption / burn) routes.

Mirrors routers/descartes.py's idempotency-checked-before-blockchain-call
pattern: the on-chain burn is irreversible and its tx_hash is not
deterministic, so a retry must be caught BEFORE the chain call, never after.
"""

from fastapi import APIRouter, Depends, Header, HTTPException, status
from postgrest.exceptions import APIError
from supabase import Client

from database import get_supabase
from dependencies import get_current_user_id
from models.schemas import ResgateCreate, ResgateResponse
from services.blockchain import (
    BlockchainNeedsReconciliation,
    BlockchainOutcomeUnknown,
    BlockchainService,
    PreparedTransaction,
    BlockchainTransactionFailed,
    get_blockchain_service,
)
from services.idempotency import (
    complete,
    get_existing,
    mark_failed,
    mark_needs_reconciliation,
    request_hash,
    reserve,
    save_prepared,
    validate_transaction_replay,
)

router = APIRouter()

# Postgres SQLSTATE for a unique-constraint violation, as surfaced by
# postgrest/supabase-py in APIError.code.
_UNIQUE_VIOLATION = "23505"


def _get_saldo_atual(supabase: Client, user_id: str) -> float:
    """
    Sum of MINT minus BURN for `user_id`.

    Must match public.get_saldo_gt() (migrations/fase4_get_saldo_gt_rpc.sql)
    exactly. That RPC is `security invoker` and keys off auth.uid(), which
    is null under this backend's service_role session - so instead of
    calling the RPC, the same arithmetic is reimplemented here directly
    against the raw rows.
    """
    result = (
        supabase.table("transacoes_tokens").select("tipo, quantidade").eq("user_id", user_id).execute()
    )
    saldo = 0.0
    for row in result.data:
        if row["tipo"] == "MINT":
            saldo += row["quantidade"]
        else:
            saldo -= row["quantidade"]
    return saldo


def _submit_and_record_burn(
    *,
    supabase: Client,
    blockchain: BlockchainService,
    prepared: PreparedTransaction,
    idempotency_key: str,
    user_id: str,
    payload: ResgateCreate,
) -> ResgateResponse:
    try:
        tx_hash = blockchain.submit_prepared_transaction(prepared)
    except BlockchainTransactionFailed as exc:
        mark_failed(supabase, key=idempotency_key, error=str(exc))
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="The Solana transaction failed; no successful burn was recorded",
        ) from exc
    except BlockchainNeedsReconciliation as exc:
        mark_needs_reconciliation(supabase, key=idempotency_key, error=str(exc))
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Burn requires reconciliation; do not submit a new transaction",
        ) from exc
    except BlockchainOutcomeUnknown as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Burn outcome is still unknown; retry with the same Idempotency-Key",
            headers={"Retry-After": "2"},
        ) from exc

    try:
        transacao_result = (
            supabase.table("transacoes_tokens")
            .insert(
                {
                    "user_id": user_id,
                    "tipo": "BURN",
                    "quantidade": payload.quantidade,
                    "tx_hash": tx_hash,
                    "idempotency_key": idempotency_key,
                }
            )
            .execute()
        )
        transacao = transacao_result.data[0]
    except APIError as exc:
        if exc.code != _UNIQUE_VIOLATION:
            raise
        existing = (
            supabase.table("transacoes_tokens")
            .select("*")
            .eq("idempotency_key", idempotency_key)
            .execute()
        )
        if not existing.data:
            raise
        transacao = existing.data[0]
        validate_transaction_replay(
            transacao,
            user_id=user_id,
            operation="BURN",
            quantity=payload.quantidade,
        )
        if transacao["tx_hash"] != tx_hash:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Idempotency-Key is already associated with a different transaction",
            ) from exc

    complete(
        supabase,
        key=idempotency_key,
        tx_hash=transacao["tx_hash"],
        resource_id=transacao["id"],
        quantity=transacao["quantidade"],
        installation=payload.instalacao_coelba,
    )

    return ResgateResponse(
        id=transacao["id"],
        status="Confirmado",
        tx_hash=transacao["tx_hash"],
        quantidade=transacao["quantidade"],
        instalacao_coelba=payload.instalacao_coelba,
        created_at=transacao["created_at"],
    )


@router.post("", response_model=ResgateResponse, status_code=status.HTTP_201_CREATED)
def create_resgate(
    payload: ResgateCreate,
    idempotency_key: str | None = Header(None, alias="Idempotency-Key"),
    user_id: str = Depends(get_current_user_id),
    supabase: Client = Depends(get_supabase),
    blockchain: BlockchainService = Depends(get_blockchain_service),
) -> ResgateResponse:
    if not idempotency_key:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Idempotency-Key header is required"
        )

    payload_hash = request_hash(payload.model_dump(mode="json"))
    reservation = get_existing(
        supabase,
        key=idempotency_key,
        user_id=user_id,
        operation="BURN",
        payload_hash=payload_hash,
        allow_pending=True,
    )
    if reservation is not None:
        if reservation.status in ("pending", "prepared"):
            existing = (
                supabase.table("transacoes_tokens")
                .select("*")
                .eq("idempotency_key", idempotency_key)
                .execute()
            )
            if existing.data:
                transacao = existing.data[0]
                validate_transaction_replay(
                    transacao,
                    user_id=user_id,
                    operation="BURN",
                    quantity=payload.quantidade,
                )
                if (
                    reservation.status == "prepared"
                    and transacao["tx_hash"] != reservation.tx_hash
                ):
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail="Recorded burn signature does not match the prepared transaction",
                    )
                complete(
                    supabase,
                    key=idempotency_key,
                    tx_hash=transacao["tx_hash"],
                    resource_id=transacao["id"],
                    quantity=transacao["quantidade"],
                    installation=payload.instalacao_coelba,
                )
                return ResgateResponse(
                    id=transacao["id"],
                    status="Confirmado",
                    tx_hash=transacao["tx_hash"],
                    quantidade=transacao["quantidade"],
                    instalacao_coelba=payload.instalacao_coelba,
                    created_at=transacao["created_at"],
                )
            if reservation.status == "prepared":
                if (
                    reservation.tx_hash is None
                    or reservation.signed_transaction is None
                    or reservation.last_valid_block_height is None
                ):
                    raise RuntimeError(
                        "Prepared burn reservation is missing signed transaction data"
                    )
                prepared = PreparedTransaction(
                    signature=reservation.tx_hash,
                    serialized_transaction=reservation.signed_transaction,
                    last_valid_block_height=reservation.last_valid_block_height,
                )
                return _submit_and_record_burn(
                    supabase=supabase,
                    blockchain=blockchain,
                    prepared=prepared,
                    idempotency_key=idempotency_key,
                    user_id=user_id,
                    payload=payload,
                )
            if not existing.data:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Burn outcome is unresolved; do not retry with a new key",
                )
        return ResgateResponse(
            id=reservation.resource_id,
            status="Confirmado",
            tx_hash=reservation.tx_hash,
            quantidade=reservation.quantity,
            instalacao_coelba=reservation.installation or payload.instalacao_coelba,
            created_at=reservation.created_at,
        )

    # 1. Idempotency replay check, BEFORE any side effect (balance check,
    # profile update, burning, persistence) - same rationale as
    # routers/descartes.py: a real Solana tx_hash is not deterministic per
    # idempotency_key, so a prior request can only be found by direct lookup.
    existing = (
        supabase.table("transacoes_tokens")
        .select("*")
        .eq("idempotency_key", idempotency_key)
        .execute()
    )
    if existing.data:
        transacao = existing.data[0]
        validate_transaction_replay(
            transacao,
            user_id=user_id,
            operation="BURN",
            quantity=payload.quantidade,
        )
        reserve(
            supabase,
            key=idempotency_key,
            user_id=user_id,
            operation="BURN",
            payload_hash=payload_hash,
        )
        complete(
            supabase,
            key=idempotency_key,
            tx_hash=transacao["tx_hash"],
            resource_id=transacao["id"],
            quantity=transacao["quantidade"],
            installation=payload.instalacao_coelba,
        )
        return ResgateResponse(
            id=transacao["id"],
            status="Confirmado",
            tx_hash=transacao["tx_hash"],
            quantidade=transacao["quantidade"],
            # Not stored on transacoes_tokens (see step 5 below) - echoed
            # back from the replayed request itself, which per the
            # Idempotency-Key contract carries the same payload as the
            # original.
            instalacao_coelba=payload.instalacao_coelba,
            created_at=transacao["created_at"],
        )

    # 2. Balance check: same MINT-minus-BURN arithmetic as
    # public.get_saldo_gt() (Fase 4 RPC). A request that can't be covered by
    # the citizen's current balance must never reach the chain.
    saldo_atual = _get_saldo_atual(supabase, user_id)
    if payload.quantidade > saldo_atual:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Insufficient balance")

    # 3. Reject non-positive amounts. Also catches e.g. a negative
    # quantidade, which would otherwise slip past the step-2 comparison
    # above (negative <= a non-negative saldo_atual).
    if payload.quantidade <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="quantidade must be greater than zero"
        )

    # 4. Wallet must already be linked before burning (same requirement as
    # descartes.py's mint path). Also carries the citizen's current
    # instalacao_coelba so it's only rewritten below when it actually
    # changed.
    user_result = (
        supabase.table("users").select("wallet_address, instalacao_coelba").eq("id", user_id).execute()
    )
    if not user_result.data or not user_result.data[0]["wallet_address"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="User has no linked wallet_address"
        )
    user_row = user_result.data[0]
    wallet_address = user_row["wallet_address"]

    reservation = reserve(
        supabase,
        key=idempotency_key,
        user_id=user_id,
        operation="BURN",
        payload_hash=payload_hash,
    )
    if reservation.status == "completed":
        return ResgateResponse(
            id=reservation.resource_id,
            status="Confirmado",
            tx_hash=reservation.tx_hash,
            quantidade=reservation.quantity,
            instalacao_coelba=reservation.installation or payload.instalacao_coelba,
            created_at=reservation.created_at,
        )

    # 5. Single-screen UX: this endpoint accepts instalacao_coelba directly
    # instead of requiring a prior PATCH /users/me call. Only written when
    # it differs, to avoid a no-op update on every redemption.
    if user_row["instalacao_coelba"] != payload.instalacao_coelba:
        supabase.table("users").update({"instalacao_coelba": payload.instalacao_coelba}).eq(
            "id", user_id
        ).execute()

    prepared = blockchain.prepare_burn_transaction(
        wallet_address, payload.quantidade, idempotency_key
    )
    save_prepared(
        supabase,
        key=idempotency_key,
        signature=prepared.signature,
        serialized_transaction=prepared.serialized_transaction,
        last_valid_block_height=prepared.last_valid_block_height,
    )
    return _submit_and_record_burn(
        supabase=supabase,
        blockchain=blockchain,
        prepared=prepared,
        idempotency_key=idempotency_key,
        user_id=user_id,
        payload=payload,
    )
