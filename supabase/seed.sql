-- Local-only demo fixture. This is not a real collection point in Salvador.
insert into public.ecopontos (id, nome, latitude, longitude, ativo)
values (
    '00000000-0000-4000-8000-000000000001',
    'PONTO FICTICIO - DEMO LOCAL (GPS SIMULADO)',
    0.0,
    0.0,
    true
)
on conflict (id) do update
set nome = excluded.nome,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    ativo = excluded.ativo;
