-- get_ao_vivo com horário de criação dos eventos (alerta de gol duplicado)
-- e restrições de segurança nos nomes
create or replace function public.get_ao_vivo()
returns jsonb language sql stable security definer set search_path = '' as $$
select jsonb_build_object(
  'agora', (extract(epoch from now()) * 1000)::bigint,
  'pelada', (select jsonb_build_object('id', p.id, 'data', p.data, 'estado', p.estado, 'versao', p.versao)
             from public.peladas p where p.status = 'ao_vivo' limit 1),
  'eventos', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', ev.id, 'client_id', ev.client_id, 'pelada_id', ev.pelada_id, 'partida', ev.partida, 'type', ev.tipo,
                 'player', ev.jogador, 'team', ev.time, 'minute', ev.minuto, 'anulado', ev.anulado,
                 'criado', (extract(epoch from ev.criado_em) * 1000)::bigint)
               order by ev.id)
             from public.eventos ev join public.peladas p on p.id = ev.pelada_id
             where p.status = 'ao_vivo'), '[]'::jsonb)
);
$$;
alter table public.jogadores add constraint jogadores_nome_seguro check (nome !~ '[<>"`\\]' and length(nome) <= 40) not valid;
alter table public.eventos add constraint eventos_jogador_seguro check (jogador !~ '[<>"`\\]') not valid;
