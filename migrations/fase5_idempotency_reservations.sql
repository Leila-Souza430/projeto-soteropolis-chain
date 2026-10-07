create table if not exists public.idempotency_operations (
    idempotency_key text primary key,
    user_id uuid not null references public.users(id) on delete cascade,
    operation text not null check (operation in ('MINT', 'BURN')),
    request_hash text not null,
    status text not null default 'pending' check (status in ('pending', 'completed')),
    tx_hash text unique,
    resource_id uuid,
    quantity double precision,
    distance_meters double precision,
    installation text,
    created_at timestamptz not null default now()
);

create index if not exists idx_idempotency_operations_user
    on public.idempotency_operations(user_id);

alter table public.idempotency_operations enable row level security;

revoke all on table public.idempotency_operations from anon, authenticated;
grant all on public.idempotency_operations to service_role;
