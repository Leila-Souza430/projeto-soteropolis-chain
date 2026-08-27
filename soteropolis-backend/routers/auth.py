"""User profile routes: wallet linking and Coelba installation number."""

from fastapi import APIRouter, Depends, HTTPException, status
from supabase import Client

from database import get_supabase
from dependencies import get_current_user_id
from models.schemas import UserPublic, UserUpdate

router = APIRouter()


@router.get("/me", response_model=UserPublic)
def get_me(
    user_id: str = Depends(get_current_user_id),
    supabase: Client = Depends(get_supabase),
) -> UserPublic:
    result = supabase.table("users").select("*").eq("id", user_id).execute()
    if not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return UserPublic(**result.data[0])


@router.patch("/me", response_model=UserPublic)
def update_me(
    payload: UserUpdate,
    user_id: str = Depends(get_current_user_id),
    supabase: Client = Depends(get_supabase),
) -> UserPublic:
    updates = payload.model_dump(exclude_unset=True)
    if not updates:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No fields to update")

    result = supabase.table("users").update(updates).eq("id", user_id).execute()
    if not result.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return UserPublic(**result.data[0])
