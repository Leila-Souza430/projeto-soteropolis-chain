drop policy if exists "Cidadãos podem enviar fotos no próprio path" on storage.objects;

create policy "Cidadãos podem enviar fotos no próprio path"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'descarte-fotos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
