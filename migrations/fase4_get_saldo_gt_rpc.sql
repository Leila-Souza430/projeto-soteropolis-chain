-- =====================================================================
-- SOTERÓPOLIS CHAIN — FASE 4: RPC get_saldo_gt (saldo de Green Tokens)
-- =====================================================================
-- Decisão do usuário: o saldo de GT do cidadão é calculado via função RPC
-- no Supabase (soma de MINT menos BURN, respeitando RLS), em vez de somar
-- manualmente no Flutter. Chamada diretamente do Flutter via
-- `supabase.rpc('get_saldo_gt')`, usando a sessão do próprio cidadão -
-- não existe endpoint FastAPI para isto (nem precisa existir).
--
-- security invoker (NÃO security definer) é proposital: a função roda com
-- as permissões de quem a chama, então a policy de RLS já existente em
-- transacoes_tokens ("Usuários podem ver as próprias transações", using
-- auth.uid() = user_id) se aplica normalmente como defesa em
-- profundidade. Sem parâmetro p_user_id - só é possível calcular o saldo
-- do próprio chamador (auth.uid()), nunca o de outro usuário.
--
-- tipo_transacao_token só tem os valores 'MINT' e 'BURN' (ver
-- database_schema.sql secao 2), entao o "else -quantidade" do case
-- abaixo so cobre BURN.
--
-- grant execute: por padrão o Postgres concede EXECUTE em novas funções a
-- PUBLIC, mas este schema foi aplicado via SQL direto (ver comentário na
-- seção 8 de database_schema.sql sobre GRANTs de tabela para
-- service_role) - então o grant abaixo é explícito para garantir que o
-- role `authenticated` (o que o Flutter usa via sessão do cidadão) possa
-- de fato chamar esta função via `supabase.rpc(...)`. Não concedido a
-- `anon` - só cidadãos autenticados devem poder calcular um saldo.
--
-- Idempotente: `create or replace function` sempre substitui a versão
-- anterior; o grant é seguro para repetir.
--
-- APLICAÇÃO: este arquivo precisa ser colado manualmente no Supabase SQL
-- Editor (Dashboard → SQL Editor) - mesma limitação de
-- fase4_user_signup_trigger.sql.
-- =====================================================================

create or replace function public.get_saldo_gt()
returns numeric
language sql
security invoker
stable
as $$
  select coalesce(sum(case when tipo = 'MINT' then quantidade else -quantidade end), 0)
  from public.transacoes_tokens
  where user_id = auth.uid();
$$;

comment on function public.get_saldo_gt() is
    'Saldo de Green Tokens (MINT - BURN) do cidadão autenticado. security invoker: roda com as permissões do chamador, RLS de transacoes_tokens se aplica normalmente. Chamada via supabase.rpc(''get_saldo_gt'') no Flutter. Fase 4 - see migrations/fase4_get_saldo_gt_rpc.sql.';

grant execute on function public.get_saldo_gt() to authenticated;

-- =====================================================================
-- FIM — FASE 4: RPC get_saldo_gt
-- =====================================================================
