-- =====================================================================
-- SOTERÓPOLIS CHAIN — FASE 1: FUNDAÇÃO DE DADOS & SEGURANÇA (SUPABASE)
-- =====================================================================
-- Este script cria as 4 tabelas principais do MVP e habilita
-- Row Level Security (RLS) com políticas restritivas por usuário.
-- =====================================================================


-- =====================================================================
-- 1. EXTENSÕES NECESSÁRIAS
-- =====================================================================
create extension if not exists "uuid-ossp";


-- =====================================================================
-- 2. TIPOS ENUMERADOS (ENUMS)
-- =====================================================================

-- Status do descarte no fluxo antifraude
create type status_descarte as enum ('Pendente', 'Validado', 'Rejeitado');

-- Tipo de transação on-chain
create type tipo_transacao_token as enum ('MINT', 'BURN');


-- =====================================================================
-- 3. TABELA: users
-- Cidadãos cadastrados na plataforma. Vinculada ao auth.users do Supabase.
-- =====================================================================
create table public.users (
    id                  uuid primary key references auth.users(id) on delete cascade,
    email               text not null unique,
    wallet_address      text unique,
    instalacao_coelba   text,
    created_at          timestamptz not null default now()
);

comment on table public.users is 'Perfis de cidadãos vinculados ao Supabase Auth. Armazena carteira Solana (Web3Auth) e conta Coelba.';


-- =====================================================================
-- 4. TABELA: ecopontos
-- Pontos físicos de coleta cadastrados, usados na validação geográfica.
-- =====================================================================
create table public.ecopontos (
    id          uuid primary key default uuid_generate_v4(),
    nome        text not null,
    latitude    double precision not null,
    longitude   double precision not null,
    ativo       boolean not null default true,
    created_at  timestamptz not null default now()
);

comment on table public.ecopontos is 'Pontos físicos de coleta de recicláveis, usados no cálculo de geofencing (Haversine).';


-- =====================================================================
-- 5. TABELA: descartes
-- Registro antifraude de cada entrega de resíduo reciclável.
-- =====================================================================
create table public.descartes (
    id              uuid primary key default uuid_generate_v4(),
    user_id         uuid not null references public.users(id) on delete cascade,
    ecoponto_id     uuid not null references public.ecopontos(id) on delete restrict,
    tipo_residuo    text not null,
    peso_estimado   double precision,
    foto_url        text not null,
    status          status_descarte not null default 'Pendente',
    created_at      timestamptz not null default now()
);

comment on table public.descartes is 'Registro de cada descarte, com foto e metadados. Base para emissão de tokens.';

create index idx_descartes_user_id on public.descartes(user_id);
create index idx_descartes_ecoponto_id on public.descartes(ecoponto_id);


-- =====================================================================
-- 6. TABELA: transacoes_tokens
-- Histórico on-chain (MINT/BURN) e auditoria financeira.
-- =====================================================================
create table public.transacoes_tokens (
    id                uuid primary key default uuid_generate_v4(),
    user_id           uuid not null references public.users(id) on delete cascade,
    tipo              tipo_transacao_token not null,
    quantidade        double precision not null check (quantidade > 0),
    tx_hash           text not null unique,
    idempotency_key   text unique,
    created_at        timestamptz not null default now()
);

comment on table public.transacoes_tokens is 'Auditoria imutável de créditos (MINT) e resgates (BURN) de Green Tokens. tx_hash garante idempotência.';
comment on column public.transacoes_tokens.idempotency_key is 'Client-supplied Idempotency-Key header from POST /descartes. Looked up BEFORE calling the blockchain service so a retry never re-mints (Fase 3 - see migrations/fase3_idempotency_key.sql). Nullable + unique: historical Phase 2 rows may lack it.';

create index idx_transacoes_user_id on public.transacoes_tokens(user_id);


-- =====================================================================
-- 7. ROW LEVEL SECURITY (RLS)
-- =====================================================================

-- Habilita RLS em todas as tabelas
alter table public.users enable row level security;
alter table public.ecopontos enable row level security;
alter table public.descartes enable row level security;
alter table public.transacoes_tokens enable row level security;


-- ---------------------------------------------------------------------
-- Políticas: users
-- Cada cidadão só pode ver/editar o próprio perfil.
-- ---------------------------------------------------------------------
create policy "Usuários podem ver o próprio perfil"
    on public.users for select
    using (auth.uid() = id);

create policy "Usuários podem atualizar o próprio perfil"
    on public.users for update
    using (auth.uid() = id);

create policy "Usuários podem inserir o próprio perfil"
    on public.users for insert
    with check (auth.uid() = id);


-- ---------------------------------------------------------------------
-- Políticas: ecopontos
-- Dados públicos de leitura (qualquer usuário autenticado pode consultar
-- os pontos de coleta). Sem inserção/edição pelo app do cidadão.
-- ---------------------------------------------------------------------
create policy "Usuários autenticados podem visualizar ecopontos ativos"
    on public.ecopontos for select
    using (auth.role() = 'authenticated' and ativo = true);


-- ---------------------------------------------------------------------
-- Políticas: descartes
-- Cada cidadão só pode ver/inserir os próprios descartes.
-- Atualização de status é reservada ao backend (service_role).
-- ---------------------------------------------------------------------
create policy "Usuários podem ver os próprios descartes"
    on public.descartes for select
    using (auth.uid() = user_id);

create policy "Usuários podem registrar os próprios descartes"
    on public.descartes for insert
    with check (auth.uid() = user_id);


-- ---------------------------------------------------------------------
-- Políticas: transacoes_tokens
-- Cada cidadão só pode ver o próprio extrato. Inserção é exclusiva
-- do backend (via service_role), nunca diretamente pelo cliente.
-- ---------------------------------------------------------------------
create policy "Usuários podem ver as próprias transações"
    on public.transacoes_tokens for select
    using (auth.uid() = user_id);


-- =====================================================================
-- 8. GRANTS PARA SERVICE_ROLE
-- =====================================================================
-- O backend (FastAPI) acessa o banco usando a service_role key, que
-- ignora as políticas de RLS por padrão. No entanto, o Postgres ainda
-- exige GRANTs explícitos de privilégio na tabela em si — sem isso,
-- mesmo o service_role recebe "permission denied" antes de qualquer
-- política de RLS ser avaliada. Projetos Supabase normalmente concedem
-- isso automaticamente; como este schema foi aplicado via SQL direto,
-- os GRANTs precisam ser explícitos.
-- =====================================================================
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;


-- =====================================================================
-- 9. TRIGGER: AUTO-CRIAÇÃO DE public.users NO SIGNUP (FASE 4)
-- =====================================================================
-- Cria automaticamente a linha correspondente em public.users sempre que
-- um novo usuário é inserido em auth.users (signup via Supabase Auth).
-- Sem isto, PATCH /users/me (routers/auth.py) 404a porque nada mais cria
-- essa linha. Ver migrations/fase4_user_signup_trigger.sql.
-- =====================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.users (id, email)
  values (new.id, new.email);
  return new;
end;
$$;

comment on function public.handle_new_user() is
    'Auto-cria a linha correspondente em public.users no signup (trigger on_auth_user_created em auth.users). Fase 4 - see migrations/fase4_user_signup_trigger.sql.';

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- =====================================================================
-- FIM DA FASE 1
-- =====================================================================
