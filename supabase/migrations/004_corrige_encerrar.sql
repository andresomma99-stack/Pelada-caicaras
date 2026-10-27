-- corrige ambiguidade de nome de variável em encerrar_pelada
create or replace function public.encerrar_pelada(p_id bigint, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_status text;
  v_partidas int := coalesce((p_payload->>'partidasRegistradas')::int, 0);
  t text; v_nome text; res text;
begin
  select status into v_status from public.peladas where id = p_id for update;
  if v_status is distinct from 'ao_vivo' then raise exception 'pelada_ja_encerrada'; end if;

  -- garante jogadores
  insert into public.jogadores (nome)
  select distinct trim(n) from (
    select jsonb_array_elements_text(p_payload->'jogadoresPorTime'->tm) as n from unnest(array['red','yellow','blue']) tm
    union select jsonb_object_keys(coalesce(p_payload->'presencaDia','{}'::jsonb))
    union select jogador from public.eventos where pelada_id = p_id and not anulado
  ) s where length(trim(n)) > 0
  on conflict (nome) do nothing;

  -- jogadores dos times (V/E/D)
  foreach t in array array['red','yellow','blue'] loop
    res := p_payload->'teamResults'->>t;
    for v_nome in select jsonb_array_elements_text(coalesce(p_payload->'jogadoresPorTime'->t, '[]'::jsonb)) loop
      insert into public.participacoes (pelada_id, jogador_id, time, resultado)
      select p_id, j.id, t, res from public.jogadores j where j.nome = trim(v_nome)
      on conflict (pelada_id, jogador_id) do update set time = excluded.time, resultado = excluded.resultado;
    end loop;
  end loop;

  -- presença (inclui resenha)
  insert into public.participacoes (pelada_id, jogador_id, presenca)
  select p_id, j.id, (kv.value)::numeric
  from jsonb_each_text(coalesce(p_payload->'presencaDia','{}'::jsonb)) kv
  join public.jogadores j on j.nome = trim(kv.key)
  on conflict (pelada_id, jogador_id) do update set presenca = excluded.presenca;

  -- gols e assistências a partir dos eventos
  insert into public.participacoes (pelada_id, jogador_id, gols, assists)
  select p_id, j.id,
         count(*) filter (where ev.tipo = 'gol'), count(*) filter (where ev.tipo = 'assist')
  from public.eventos ev join public.jogadores j on j.nome = ev.jogador
  where ev.pelada_id = p_id and not ev.anulado and ev.partida <= v_partidas
  group by j.id
  on conflict (pelada_id, jogador_id) do update set gols = excluded.gols, assists = excluded.assists;

  -- goleiros
  insert into public.goleiros_dia (pelada_id, goleiro, gols_tomados, vitorias, derrotas)
  select p_id, kv.key, coalesce((kv.value->>'gols_tomados')::int,0),
         coalesce((kv.value->>'vitorias')::int,0), coalesce((kv.value->>'derrotas')::int,0)
  from jsonb_each(coalesce(p_payload->'goleirosData','{}'::jsonb)) kv
  on conflict (pelada_id, goleiro) do update set gols_tomados = excluded.gols_tomados,
     vitorias = excluded.vitorias, derrotas = excluded.derrotas;

  update public.peladas set status = 'encerrada', encerrada_em = now() where id = p_id;

  return jsonb_build_object(
    'gols',    coalesce((select jsonb_object_agg(j.nome, x.gols) from public.participacoes x join public.jogadores j on j.id = x.jogador_id where x.pelada_id = p_id and x.gols > 0), '{}'::jsonb),
    'assists', coalesce((select jsonb_object_agg(j.nome, x.assists) from public.participacoes x join public.jogadores j on j.id = x.jogador_id where x.pelada_id = p_id and x.assists > 0), '{}'::jsonb));
end $$;

