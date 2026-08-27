"""Ecopontos (collection point) routes."""

from fastapi import APIRouter, Depends
from supabase import Client

from database import get_supabase
from models.schemas import EcopontoPublic

router = APIRouter()


@router.get("", response_model=list[EcopontoPublic])
def list_ecopontos(supabase: Client = Depends(get_supabase)) -> list[EcopontoPublic]:
    result = supabase.table("ecopontos").select("*").eq("ativo", True).execute()
    return [EcopontoPublic(**row) for row in result.data]
