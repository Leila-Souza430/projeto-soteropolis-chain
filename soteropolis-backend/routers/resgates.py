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
from services.blockchain import BlockchainService, get_blockchain_service

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

    # 1. Idempotency replay check, BEFORE any side effect (balance check,
    # profile update, burning, persistence) - same rationale as
    # routers/descartes.py: a real Solana tx_hash is not deterministic per
    # idempotency_key, so a prior request can only be found by direct lookup.
    existing = (
        supabase.table("transacoes_tokens").select("*").eq("idempotency_key", idempotency_key).execute()
    )
    if existing.data:
        transacao = existing.data[0]
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

    # 5. Single-screen UX: this endpoint accepts instalacao_coelba directly
    # instead of requiring a prior PATCH /users/me call. Only written when
    # it differs, to avoid a no-op update on every redemption.
    if user_row["instalacao_coelba"] != payload.instalacao_coelba:
        supabase.table("users").update({"instalacao_coelba": payload.instalacao_coelba}).eq(
            "id", user_id
        ).execute()

    # 6. Burn. Not reached on replay (see step 1) - a retry never spends a
    # second real transaction.
    tx_hash = blockchain.burn_tokens(wallet_address, payload.quantidade, idempotency_key)

    # 7. Record the BURN transaction. Step 1 and this insert race on
    # concurrent requests sharing the same Idempotency-Key; a 23505 unique
    # violation here means the other request won that race - replay its
    # result instead of double-recording the burn.
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
            supabase.table("transacoes_tokens").select("*").eq("idempotency_key", idempotency_key).execute()
        )
        if not existing.data:
            raise
        transacao = existing.data[0]

    return ResgateResponse(
        id=transacao["id"],
        status="Confirmado",
        tx_hash=transacao["tx_hash"],
        quantidade=transacao["quantidade"],
        instalacao_coelba=payload.instalacao_coelba,
        created_at=transacao["created_at"],
    )
