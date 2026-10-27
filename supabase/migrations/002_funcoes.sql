-- Pelada de Quinta — funções (API do site)
-- Leitura: get_dados() devolve exatamente o formato que o site usava do Apps Script.
-- Escrita: só por estas funções; ninguém altera as tabelas diretamente.

-- ───────────────────────── LEITURA ─────────────────────────
create or replace function public.get_dados()
returns jsonb language sql stable security definer set search_path = '' as $$
with enc as (
  select id, data from public.peladas where status = 'encerrada'
),
res_dates as (   -- peladas com resultado (V/E/D): são as "colunas" das tabelas
  select e.id, e.data, row_number() over (order by e.data) as idx
  from enc e
  where exists (select 1 from public.participacoes x where x.pelada_id = e.id and x.resultado is not null)
),
last10 as (select id from enc order by data desc limit 10),
pa as (
  select x.*, j.nome, e.data
  from public.participacoes x
  join enc e on e.id = x.pelada_id
  join public.jogadores j on j.id = x.jogador_id
),
rk as (
  select nome,
         count(resultado)                           as j,
         count(*) filter (where resultado = 'V')    as v,
         count(*) filter (where resultado = 'E')    as e,
         count(*) filter (where resultado = 'D')    as d,
         jsonb_agg(resultado order by data) filter (where resultado is not null) as forma
  from pa group by nome having count(resultado) > 0
),
ranking as (
  select coalesce(jsonb_agg(jsonb_build_object(
           'name', nome, 'pts', 3*v + e, 'j', j, 'v', v, 'e', e, 'd', d,
           'pct', (3*v + e)::float8 / (3*j), 'forma', forma)
         order by 3*v + e desc, (3*v + e)::float8 / (3*j) desc, nome), '[]'::jsonb) as js
  from rk
),
tot as (
  select nome, sum(gols) as gols, sum(assists) as assists from pa group by nome
),
serie as (   -- jogador × pelada-com-resultado, para os arrays por pelada
  select t.nome, r.idx, coalesce(x.gols,0) as gols, coalesce(x.assists,0) as assists,
         coalesce(x.presenca,0) as presenca
  from tot t cross join res_dates r
  left join pa x on x.nome = t.nome and x.pelada_id = r.id
),
artilharia as (
  select coalesce(jsonb_agg(o order by (o->>'gols')::int desc, (o->>'media')::numeric desc, o->>'name'), '[]'::jsonb) as js
  from (
    select jsonb_build_object(
      'name', t.nome, 'gols', t.gols, 'j', coalesce(rk.j,0),
      'media', case when coalesce(rk.j,0) > 0 then round(t.gols::numeric / rk.j, 2) else 0 end,
      'peladas', (select jsonb_agg(s.gols order by s.idx) from serie s where s.nome = t.nome)) as o
    from tot t left join rk on rk.nome = t.nome
    where t.gols > 0
  ) q
),
assistencias as (
  select coalesce(jsonb_agg(o order by (o->>'assists')::int desc, (o->>'media')::numeric desc, o->>'name'), '[]'::jsonb) as js
  from (
    select jsonb_build_object(
      'name', t.nome, 'assists', t.assists, 'j', coalesce(rk.j,0),
      'media', case when coalesce(rk.j,0) > 0 then round(t.assists::numeric / rk.j, 2) else 0 end,
      'peladas', (select jsonb_agg(s.assists order by s.idx) from serie s where s.nome = t.nome)) as o
    from tot t left join rk on rk.nome = t.nome
    where t.assists > 0
  ) q
),
pres as (
  select nome,
         sum(presenca) as anual,
         coalesce(sum(presenca) filter (where pelada_id in (select id from last10)), 0) as u10
  from pa where presenca is not null group by nome
),
presenca as (
  select coalesce(jsonb_agg(jsonb_build_object(
           'name', p.nome, 'u10', p.u10, 'anual', p.anual,
           'dates', (select jsonb_agg(s.presenca order by s.idx) from serie s where s.nome = p.nome))
         order by p.u10 desc, p.anual desc, p.nome), '[]'::jsonb) as js
  from pres p
),
historico as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'data', to_char(r.data, 'DD/MM/YYYY'),
    'jogadores', coalesce((select jsonb_agg(jsonb_build_object('name', x.nome, 'res', x.resultado) order by x.nome)
                           from pa x where x.pelada_id = r.id and x.resultado is not null), '[]'::jsonb),
    'gols',      coalesce((select jsonb_object_agg(x.nome, x.gols) from pa x where x.pelada_id = r.id and x.gols > 0), '{}'::jsonb),
    'assists',   coalesce((select jsonb_object_agg(x.nome, x.assists) from pa x where x.pelada_id = r.id and x.assists > 0), '{}'::jsonb)
  ) order by r.idx), '[]'::jsonb) as js
  from res_dates r
),
gol as (
  select coalesce(jsonb_object_agg(goleiro, o), '{}'::jsonb) as js
  from (
    select g.goleiro, jsonb_build_object(
      'gols_tomados', sum(g.gols_tomados), 'vitorias', sum(g.vitorias), 'derrotas', sum(g.derrotas),
      'porData', jsonb_object_agg(to_char(e.data,'DD/MM'), jsonb_build_object(
          'gols_tomados', g.gols_tomados, 'vitorias', g.vitorias, 'derrotas', g.derrotas))) as o
    from public.goleiros_dia g join enc e on e.id = g.pelada_id
    group by g.goleiro
  ) q
)
select jsonb_build_object(
  'ok', true,
  'rankingData',      (select js from ranking),
  'artilhariaData',   (select js from artilharia),
  'assistenciasData', (select js from assistencias),
  'presencaData',     (select js from presenca),
  'totalPeladas',     (select count(*) from res_dates),
  'datasPeladas',     coalesce((select jsonb_agg(to_char(data,'DD/MM') order by idx) from res_dates), '[]'::jsonb),
  'historicoPeladas', (select js from historico),
  'goleiroStats',     (select js from gol),
  'jogadores',        coalesce((select jsonb_agg(nome order by nome) from public.jogadores), '[]'::jsonb)
);
$$;

-- Estado da pelada ao vivo (se houver) + eventos + relógio do servidor
create or replace function public.get_ao_vivo()
returns jsonb language sql stable security definer set search_path = '' as $$
select jsonb_build_object(
  'agora', (extract(epoch from now()) * 1000)::bigint,
  'pelada', (select jsonb_build_object('id', p.id, 'data', p.data, 'estado', p.estado, 'versao', p.versao)
             from public.peladas p where p.status = 'ao_vivo' limit 1),
  'eventos', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', ev.id, 'client_id', ev.client_id, 'partida', ev.partida, 'type', ev.tipo,
                 'player', ev.jogador, 'team', ev.time, 'minute', ev.minuto, 'anulado', ev.anulado)
               order by ev.id)
             from public.eventos ev join public.peladas p on p.id = ev.pelada_id
             where p.status = 'ao_vivo'), '[]'::jsonb)
);
$$;

-- ───────────────────────── ESCRITA ─────────────────────────
create or replace function public.adicionar_jogador(p_nome text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_nome is null or length(trim(p_nome)) = 0 or length(p_nome) > 40 then
    raise exception 'nome_invalido';
  end if;
  insert into public.jogadores (nome) values (trim(p_nome)) on conflict (nome) do nothing;
end $$;

create or replace function public.iniciar_ao_vivo(p_data date, p_estado jsonb, p_aparelho text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  if exists (select 1 from public.peladas where status = 'ao_vivo') then
    raise exception 'ja_existe_ao_vivo';
  end if;
  if exists (select 1 from public.peladas where data = p_data and status = 'encerrada') then
    raise exception 'data_ja_encerrada';
  end if;
  if pg_column_size(p_estado) > 200000 then raise exception 'estado_grande'; end if;
  insert into public.peladas (data, status, estado, versao)
  values (p_data, 'ao_vivo', p_estado, 1) returning id into v_id;
  insert into public.log_estado (pelada_id, versao, acao, aparelho, estado)
  values (v_id, 1, 'iniciar', left(p_aparelho, 64), p_estado);
  return jsonb_build_object('id', v_id, 'versao', 1);
end $$;

create or replace function public.salvar_estado(p_id bigint, p_versao int, p_estado jsonb,
                                                p_acao text default null, p_aparelho text default null)
returns int language plpgsql security definer set search_path = '' as $$
declare v_nova int;
begin
  if pg_column_size(p_estado) > 200000 then raise exception 'estado_grande'; end if;
  update public.peladas set estado = p_estado, versao = versao + 1
   where id = p_id and versao = p_versao and status = 'ao_vivo'
  returning versao into v_nova;
  if v_nova is null then raise exception 'conflito'; end if;
  insert into public.log_estado (pelada_id, versao, acao, aparelho, estado)
  values (p_id, v_nova, left(p_acao, 64), left(p_aparelho, 64), p_estado);
  return v_nova;
end $$;

create or replace function public.registrar_evento(p_id bigint, p_client_id uuid, p_partida int, p_tipo text,
                                                   p_jogador text, p_time text, p_minuto int,
                                                   p_aparelho text default null)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_ev bigint;
begin
  if not exists (select 1 from public.peladas where id = p_id and status = 'ao_vivo') then
    raise exception 'pelada_nao_esta_ao_vivo';
  end if;
  insert into public.eventos (pelada_id, client_id, partida, tipo, jogador, time, minuto, aparelho)
  values (p_id, p_client_id, p_partida, p_tipo, left(p_jogador, 40), p_time, greatest(1, least(p_minuto, 999)), left(p_aparelho, 64))
  on conflict (client_id) do nothing
  returning id into v_ev;
  if v_ev is null then select id into v_ev from public.eventos where client_id = p_client_id; end if;
  return v_ev;
end $$;

create or replace function public.anular_evento(p_evento_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.eventos ev set anulado = true, anulado_em = now()
    from public.peladas p
   where ev.id = p_evento_id and p.id = ev.pelada_id and p.status = 'ao_vivo';
end $$;

-- Encerra a pelada do dia: grava tudo em participacoes / goleiros_dia de uma vez.
-- Gols e assistências vêm dos eventos registrados (não anulados) das partidas concluídas.
create or replace function public.encerrar_pelada(p_id bigint, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_status text;
  v_partidas int := coalesce((p_payload->>'partidasRegistradas')::int, 0);
  t text; nome text; res text;
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
    for nome in select jsonb_array_elements_text(coalesce(p_payload->'jogadoresPorTime'->t, '[]'::jsonb)) loop
      insert into public.participacoes (pelada_id, jogador_id, time, resultado)
      select p_id, j.id, t, res from public.jogadores j where j.nome = trim(nome)
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

create or replace function public.descartar_pelada(p_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.peladas set status = 'descartada' where id = p_id and status = 'ao_vivo';
end $$;

-- leve, para o keep-alive
create or replace function public.ping() returns text language sql stable security definer set search_path = '' as $$
  select 'ok ' || (select count(*) from public.peladas)::text;
$$;

grant execute on function public.get_dados(), public.get_ao_vivo(), public.adicionar_jogador(text),
  public.iniciar_ao_vivo(date, jsonb, text), public.salvar_estado(bigint, int, jsonb, text, text),
  public.registrar_evento(bigint, uuid, int, text, text, text, int, text), public.anular_evento(bigint),
  public.encerrar_pelada(bigint, jsonb), public.descartar_pelada(bigint), public.ping()
  to anon, authenticated;
