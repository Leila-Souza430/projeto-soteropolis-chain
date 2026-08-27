"""Application configuration, loaded from environment variables (.env)."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Supabase
    supabase_url: str
    supabase_service_role_key: str
    supabase_anon_key: str

    # Geofencing / tokenomics (see SPEC.md 3.2 and 3.3)
    geofence_tolerance_meters: float = 50
    token_rate_per_kg: float
    token_fixed_amount: float

    # Per-call mint cap (audit finding: mint_tokens had no upper bound). A
    # single legitimate recycling drop-off should never remotely approach
    # this - it only exists to stop a bug/compromise from over-minting.
    # Scoped to the /descartes mint path only.
    max_quantidade_tokens_per_descarte: float = 1000.0

    # Blockchain integration mode: "mock" (Phase 2) or "solana" (Phase 3)
    blockchain_mode: str = "mock"

    # Solana (Phase 3). Optional/None-defaulted so BLOCKCHAIN_MODE=mock keeps
    # booting with zero Solana config present - SolanaBlockchainService
    # validates these itself, only when actually constructed.
    solana_rpc_url: str | None = None
    solana_program_id: str | None = None
    solana_gt_mint_address: str | None = None
    solana_authority_keypair_path: str | None = None
    solana_gt_decimals: int = 2
    solana_commitment: str = "confirmed"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


settings = Settings()
