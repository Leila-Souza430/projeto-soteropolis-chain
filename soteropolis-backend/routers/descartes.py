"""Descartes (waste drop-off) routes - the antifraude + minting critical path."""

from fastapi import APIRouter, Depends, Header, HTTPException, status
from postgrest.exceptions import APIError
from supabase import Client

from config import settings
from database import get_supabase
from dependencies import get_current_user_id
from models.schemas import DescarteCreate, DescarteResponse, StatusDescarte
from services.blockchain import BlockchainService, get_blockchain_service
from services.idempotency import (
    complete,
    get_existing,
    request_hash,
    reserve,
    validate_transaction_replay,
)
from utils.geo import haversine_distance_meters

router = APIRouter()

# Postgres SQLSTATE for a unique-constraint violation, as surfaced by
# postgrest/supabase-py in APIError.code.
_UNIQUE_VIOLATION = "23505"


def _mark_descarte_validated(supabase: Client, descarte_id: str) -> None:
    result = (
        supabase.table("descartes")
        .update({"status": StatusDescarte.VALIDADO.value})
        .eq("id", descarte_id)
        .execute()
    )
    if not result.data:
        raise RuntimeError(f"Could not mark descarte {descarte_id!r} as validated")


@router.post("", response_model=DescarteResponse, status_code=status.HTTP_201_CREATED)
def create_descarte(
    payload: DescarteCreate,
    idempotency_key: str | None = Header(None, alias="Idempotency-Key"),
    user_id: str = Depends(get_current_user_id),
    supabase: Client = Depends(get_supabase),
    blockchain: BlockchainService = Depends(get_blockchain_service),
) -> DescarteResponse:
    if not idempotency_key:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Idempotency-Key header is required"
        )

    payload_hash = request_hash(payload.model_dump(mode="json"))
    reservation = get_existing(
        supabase,
        key=idempotency_key,
        user_id=user_id,
        operation="MINT",
        payload_hash=payload_hash,
    )
    if reservation is not None:
        return DescarteResponse(
            id=reservation.resource_id,
            status=StatusDescarte.VALIDADO,
            distancia_metros=reservation.distance_meters or 0.0,
            tx_hash=reservation.tx_hash,
            quantidade_tokens=reservation.quantity,
            created_at=reservation.created_at,
        )

    if payload.peso_estimado is not None:
        quantidade_tokens = payload.peso_estimado * settings.token_rate_per_kg
    else:
        quantidade_tokens = settings.token_fixed_amount

    if quantidade_tokens > settings.max_quantidade_tokens_per_descarte:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"quantidade_tokens ({quantidade_tokens}) exceeds the per-descarte cap "
                f"({settings.max_quantidade_tokens_per_descarte})"
            ),
        )

    # 1. Idempotency replay check, BEFORE any side effect (geofencing write,
    # minting, persistence). A real Solana tx_hash is not deterministic per
    # idempotency_key the way the Phase 2 mock's sha256 was (it depends on a
    # fresh blockhash per send), so a prior request can no longer be found
    # by re-deriving its tx_hash - it must be looked up directly.
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
            operation="MINT",
            quantity=quantidade_tokens,
        )
        reserve(
            supabase,
            key=idempotency_key,
            user_id=user_id,
            operation="MINT",
            payload_hash=payload_hash,
        )
        complete(
            supabase,
            key=idempotency_key,
            tx_hash=transacao["tx_hash"],
            resource_id=transacao["id"],
            quantity=transacao["quantidade"],
        )
        return DescarteResponse(
            id=transacao["id"],
            status=StatusDescarte.VALIDADO,
            # Not stored on transacoes_tokens and not recomputed on replay
            # (no geofencing/mint side effect runs here) - 0 signals "this
            # is a replay of an already-validated descarte", not a fresh
            # GPS measurement.
            distancia_metros=0.0,
            tx_hash=transacao["tx_hash"],
            quantidade_tokens=transacao["quantidade"],
            created_at=transacao["created_at"],
        )

    # 2. Ecoponto must exist and be active.
    ecoponto_result = supabase.table("ecopontos").select("*").eq("id", str(payload.ecoponto_id)).execute()
    if not ecoponto_result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Ecoponto not found")
    ecoponto = ecoponto_result.data[0]
    if not ecoponto["ativo"]:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Ecoponto not found")

    # 3. Geofencing (SPEC.md 3.2): distance between the reported GPS fix and
    # the ecoponto's registered coordinates.
    distancia_metros = haversine_distance_meters(
        payload.latitude, payload.longitude, ecoponto["latitude"], ecoponto["longitude"]
    )

    descarte_base = {
        "user_id": user_id,
        "ecoponto_id": str(payload.ecoponto_id),
        "tipo_residuo": payload.tipo_residuo,
        "peso_estimado": payload.peso_estimado,
        "foto_url": payload.foto_url,
    }

    # 4. Out of range: record the attempt for audit (never drop it silently),
    # reject, and stop before any minting happens.
    if distancia_metros > settings.geofence_tolerance_meters:
        descarte_result = supabase.table("descartes").insert(
            {**descarte_base, "status": StatusDescarte.REJEITADO.value}
        ).execute()
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "message": "Descarte fora da área de tolerância do ecoponto",
                "descarte_id": descarte_result.data[0]["id"],
                "distancia_metros": distancia_metros,
                "tolerancia_metros": settings.geofence_tolerance_meters,
            },
        )

    # 5. Wallet must already be linked before any descarte is persisted.
    # user_id comes from the JWT dependency, never from the request body.
    user_result = supabase.table("users").select("wallet_address").eq("id", user_id).execute()
    if not user_result.data or not user_result.data[0]["wallet_address"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="User has no linked wallet_address"
        )
    wallet_address = user_result.data[0]["wallet_address"]

    reservation = reserve(
        supabase,
        key=idempotency_key,
        user_id=user_id,
        operation="MINT",
        payload_hash=payload_hash,
    )
    if reservation.status == "completed":
        return DescarteResponse(
            id=reservation.resource_id,
            status=StatusDescarte.VALIDADO,
            distancia_metros=reservation.distance_meters or 0.0,
            tx_hash=reservation.tx_hash,
            quantidade_tokens=reservation.quantity,
            created_at=reservation.created_at,
        )

    # 7. Keep the attempt pending until its mint is confirmed and recorded.
    descarte = supabase.table("descartes").insert(
        {**descarte_base, "status": StatusDescarte.PENDENTE.value}
    ).execute().data[0]

    # 8. Mint. The reservation prevents concurrent requests with the same key
    # from reaching the blockchain twice.
    tx_hash = blockchain.mint_tokens(wallet_address, quantidade_tokens, idempotency_key)

    # 9. Record the MINT transaction. The step-1 check and this insert race
    # on concurrent requests sharing the same Idempotency-Key; a 23505
    # unique violation on idempotency_key here means the other request won
    # that race - replay its result instead of crediting the user twice.
    try:
        transacao_result = (
            supabase.table("transacoes_tokens")
            .insert(
                {
                    "user_id": user_id,
                    "tipo": "MINT",
                    "quantidade": quantidade_tokens,
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
            operation="MINT",
            quantity=quantidade_tokens,
        )

    # 10. Response combines the descarte record with the (possibly replayed)
    # token transaction.
    complete(
        supabase,
        key=idempotency_key,
        tx_hash=transacao["tx_hash"],
        resource_id=descarte["id"],
        quantity=transacao["quantidade"],
        distance_meters=distancia_metros,
    )
    _mark_descarte_validated(supabase, descarte["id"])

    return DescarteResponse(
        id=descarte["id"],
        status=StatusDescarte.VALIDADO,
        distancia_metros=distancia_metros,
        tx_hash=transacao["tx_hash"],
        quantidade_tokens=transacao["quantidade"],
        created_at=descarte["created_at"],
    )
