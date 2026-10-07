"""Pydantic v2 request/response models."""

from datetime import datetime
from enum import Enum
from uuid import UUID

from pydantic import BaseModel, Field


class StatusDescarte(str, Enum):
    PENDENTE = "Pendente"
    VALIDADO = "Validado"
    REJEITADO = "Rejeitado"


class UserPublic(BaseModel):
    id: UUID
    email: str
    wallet_address: str | None = None
    instalacao_coelba: str | None = None
    created_at: datetime


class UserUpdate(BaseModel):
    wallet_address: str | None = None
    instalacao_coelba: str | None = None


class EcopontoPublic(BaseModel):
    id: UUID
    nome: str
    latitude: float
    longitude: float
    ativo: bool
    created_at: datetime


class DescarteCreate(BaseModel):
    ecoponto_id: UUID
    latitude: float = Field(ge=-90, le=90, allow_inf_nan=False)
    longitude: float = Field(ge=-180, le=180, allow_inf_nan=False)
    tipo_residuo: str = Field(min_length=1)
    peso_estimado: float | None = Field(default=None, ge=0, allow_inf_nan=False)
    foto_url: str = Field(min_length=1)


class DescarteResponse(BaseModel):
    id: UUID
    status: StatusDescarte
    distancia_metros: float
    tx_hash: str | None = None
    quantidade_tokens: float | None = None
    created_at: datetime


class ResgateCreate(BaseModel):
    quantidade: float = Field(allow_inf_nan=False)
    # Exactly 10 digits. This is an arbitrary mock format for the simulated
    # Coelba integration (Fase 5) - SPEC.md does not document a real one.
    instalacao_coelba: str = Field(pattern=r"^\d{10}$")


class ResgateResponse(BaseModel):
    id: UUID
    status: str
    tx_hash: str
    quantidade: float
    instalacao_coelba: str
    created_at: datetime
