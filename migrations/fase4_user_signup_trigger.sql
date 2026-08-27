-- =====================================================================
-- SOTERÓPOLIS CHAIN — FASE 4: TRIGGER DE AUTO-CRIAÇÃO DE public.users
-- =====================================================================
-- Hoje nada cria a linha em public.users quando um cidadão se cadastra via
-- Supabase Auth - PATCH /users/me faz um UPDATE puro (routers/auth.py) e
-- retorna 404 se a linha ainda não existir. Este trigger cobre esse gap:
-- toda vez que uma linha é inserida em auth.users (signup), uma linha
-- correspondente é automaticamente criada em public.users.
--
-- security definer é necessário aqui: a função roda no contexto de um
-- trigger disparado em auth.users, e o cidadão que está se cadastrando
-- ainda não tem uma sessão autenticada com permissão de insert em
-- public.users no momento exato do signup.
--
-- Idempotente: seguro para rodar mais de uma vez.
--   - `create or replace function` sempre substitui a versão anterior.
--   - Triggers não suportam `create or replace`, então o trigger é
--     recriado via `drop trigger if exists` + `create trigger`.
--
-- APLICAÇÃO: este arquivo precisa ser colado manualmente no Supabase SQL
-- Editor (Dashboard → SQL Editor) - não há credenciais/DDL access neste
-- ambiente para aplicá-lo automaticamente (mesma limitação documentada
-- para migrations/fase3_idempotency_key.sql).
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
-- FIM — FASE 4: trigger de signup
-- =====================================================================
