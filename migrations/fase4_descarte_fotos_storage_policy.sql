-- =====================================================================
-- SOTERÓPOLIS CHAIN — FASE 4: POLÍTICA DE STORAGE (bucket descarte-fotos)
-- =====================================================================
-- O bucket 'descarte-fotos' já foi criado (public = true, file_size_limit
-- = 10485760 bytes / 10 MB, allowed_mime_types = image/jpeg, image/png,
-- image/webp, image/heic) via o Storage API do client Python
-- service_role (database.py) - criação de bucket não é DDL bruto e não
-- tem a limitação de acesso descrita abaixo.
--
-- Leitura pública já funciona automaticamente para esse bucket, sem
-- precisar de policy de RLS: o endpoint
-- /storage/v1/object/public/descarte-fotos/{path} ignora RLS porque o
-- bucket é público.
--
-- O que FALTA e EXIGE esta migration: permitir que um cidadão autenticado
-- faça upload (INSERT) apenas dentro do próprio prefixo de path. RLS em
-- storage.objects é uma tabela real no schema storage, então "criar uma
-- policy" aqui é DDL - mesma limitação de fase4_user_signup_trigger.sql /
-- fase4_get_saldo_gt_rpc.sql (sem connection string/psql/Management API
-- neste ambiente).
--
-- CONVENÇÃO DE PATH (o app Flutter precisa seguir isto exatamente):
--   descarte-fotos/{user_id}/{uuid}.jpg
-- onde {user_id} é o auth.uid() do cidadão fazendo upload (mesmo valor
-- que public.users.id), e {uuid} é um nome de arquivo gerado client-side
-- (evita colisão entre uploads do mesmo usuário). A policy abaixo valida
-- exatamente esse primeiro segmento do path contra auth.uid().
--
-- Idempotente: guardado com `drop policy if exists` antes de recriar -
-- policies, como triggers, não suportam `create or replace`.
--
-- APLICAÇÃO: este arquivo precisa ser colado manualmente no Supabase SQL
-- Editor (Dashboard → SQL Editor).
-- =====================================================================

drop policy if exists "Cidadãos podem enviar fotos no próprio path" on storage.objects;

create policy "Cidadãos podem enviar fotos no próprio path"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'descarte-fotos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- =====================================================================
-- FIM — FASE 4: política de storage (descarte-fotos)
-- =====================================================================
