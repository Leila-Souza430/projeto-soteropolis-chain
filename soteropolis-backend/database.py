"""
Supabase client for this backend.

This client is built with the service_role key, which bypasses Row Level
Security entirely. That is intentional: RLS policies only let a citizen
read/write their OWN `users` and `descartes` rows, and never let a client
insert into `transacoes_tokens` or flip a descarte's status between
'Pendente' / 'Validado' / 'Rejeitado'. Those decisions (geofencing,
idempotent minting, audit trail writes) are business logic that must be
arbitrated server-side, so this backend is the one trusted layer allowed
to bypass RLS.

The service_role key must NEVER be shipped to the Flutter app or any other
client-facing code - it only ever lives in this backend's environment.
"""

from supabase import Client, create_client

from config import settings

supabase: Client = create_client(settings.supabase_url, settings.supabase_service_role_key)


def get_supabase() -> Client:
    """FastAPI dependency exposing the shared service-role Supabase client."""
    return supabase
