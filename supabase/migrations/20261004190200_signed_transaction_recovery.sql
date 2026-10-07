alter table public.idempotency_operations
    add column if not exists signed_transaction text,
    add column if not exists last_valid_block_height bigint,
    add column if not exists last_error text,
    add column if not exists updated_at timestamptz not null default now();

alter table public.idempotency_operations
    drop constraint if exists idempotency_operations_status_check;

alter table public.idempotency_operations
    add constraint idempotency_operations_status_check
    check (status in ('pending', 'prepared', 'needs_reconciliation', 'failed', 'completed'));

alter table public.idempotency_operations enable row level security;

revoke all on table public.idempotency_operations from anon, authenticated;
grant all on table public.idempotency_operations to service_role;

comment on column public.idempotency_operations.signed_transaction is
    'Base64-encoded signed transaction used for same-signature retransmission. Restricted to service_role; never log or expose to clients.';
