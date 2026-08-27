-- =====================================================================
-- SOTERÓPOLIS CHAIN — FASE 3: IDEMPOTENCY KEY (transacoes_tokens)
-- =====================================================================
-- Phase 2's idempotency trick derived tx_hash deterministically from the
-- Idempotency-Key header (MockBlockchainService only), so a duplicate
-- insert attempt on the tx_hash UNIQUE constraint caught retries. Real
-- Solana signatures depend on a fresh blockhash per send and are NOT
-- deterministic per idempotency key, so that trick silently stops working
-- once SolanaBlockchainService is live - a client retry would mint twice.
--
-- This migration adds a proper idempotency_key column so
-- routers/descartes.py can look up a prior request BEFORE calling the
-- blockchain service, independent of tx_hash.
--
-- Postgres allows multiple NULL values under a UNIQUE constraint, so this
-- is safe to add without a NOT NULL default - historical rows that predate
-- idempotency-key tracking simply stay NULL (except the two backfilled
-- below).
--
-- Idempotent: safe to run more than once against the same database.
-- =====================================================================

alter table public.transacoes_tokens
    add column if not exists idempotency_key text;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'transacoes_tokens_idempotency_key_key'
          and conrelid = 'public.transacoes_tokens'::regclass
    ) then
        alter table public.transacoes_tokens
            add constraint transacoes_tokens_idempotency_key_key unique (idempotency_key);
    end if;
end $$;

comment on column public.transacoes_tokens.idempotency_key is
    'Client-supplied Idempotency-Key header from POST /descartes. Looked up BEFORE calling the blockchain service so a retry never re-mints. Nullable + unique: historical Phase 2 rows may lack it, Postgres allows multiple NULLs under UNIQUE.';


-- =====================================================================
-- Backfill: the two Phase 2 mock-mode rows created before this column
-- existed. Matched by their known (mock, sha256-derived) tx_hash so a
-- retry of either original idempotency key still replays correctly
-- instead of double-minting.
-- =====================================================================
update public.transacoes_tokens
set idempotency_key = 'teste-abc-001'
where tx_hash = '8f58dde4ed03b5de09ec7e4e7ef4881f0d0bb199c0dcdba4e7f3e4b39b33ec81';

update public.transacoes_tokens
set idempotency_key = 'teste-abc-002'
where tx_hash = '4ec121baf89e3924e884378787601a334db715a8ddf715c56123d6e9b3b3ca90';

-- =====================================================================
-- FIM — FASE 3: idempotency_key
-- =====================================================================
