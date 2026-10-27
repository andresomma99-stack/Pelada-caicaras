-- Variação de posições: as tabelas são calculadas "até a pelada anterior" e
-- comparadas com as atuais. A seta muda sozinha quando outra pelada é encerrada.

create or replace function public._tabelas(p_ate date)
returns jsonb language sql stable set search_path = '' as $$
with enc as (
  select id, data from public.peladas where status = 'encerrada' and data <= p_ate
),
res_dates as (
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
tot as (
  select nome, sum(gols) as gols, sum(assists) as assists from pa group by nome
),
serie as (
  select t.nome, r.idx, coalesce(x.gols,0) as gols, coalesce(x.assists,0) as assists,
         coalesce(x.presenca,0) as presenca
  from tot t cross join res_dates r
  left join pa x on x.nome = t.nome and x.pelada_id = r.id
),
pres as (
  select nome,
         sum(presenca) as anual,
         coalesce(sum(presenca) filter (where pelada_id in (select id from last10)), 0) as u10
  from pa where presenca is not null group by nome
)
select jsonb_build_object(
  'ranking', (select coalesce(jsonb_agg(jsonb_build_object(
           'name', nome, 'pts', 3*v + e, 'j', j, 'v', v, 'e', e, 'd', d,
           'pct', (3*v + e)::float8 / (3*j), 'forma', forma)
         order by 3*v + e desc, (3*v + e)::float8 / (3*j) desc, nome), '[]'::jsonb) from rk),
  'artilharia', (select coalesce(jsonb_agg(o order by (o->>'gols')::int desc, (o->>'media')::numeric desc, o->>'name'), '[]'::jsonb)
    from (select jsonb_build_object(
      'name', t.nome, 'gols', t.gols, 'j', coalesce(rk.j,0),
      'media', case when coalesce(rk.j,0) > 0 then round(t.gols::numeric / rk.j, 2) else 0 end,
      'peladas', (select jsonb_agg(s.gols order by s.idx) from serie s where s.nome = t.nome)) as o
      from tot t left join rk on rk.nome = t.nome where t.gols > 0) q),
  'assistencias', (select coalesce(jsonb_agg(o order by (o->>'assists')::int desc, (o->>'media')::numeric desc, o->>'name'), '[]'::jsonb)
    from (select jsonb_build_object(
      'name', t.nome, 'assists', t.assists, 'j', coalesce(rk.j,0),
      'media', case when coalesce(rk.j,0) > 0 then round(t.assists::numeric / rk.j, 2) else 0 end,
      'peladas', (select jsonb_agg(s.assists order by s.idx) from serie s where s.nome = t.nome)) as o
      from tot t left join rk on rk.nome = t.nome where t.assists > 0) q),
  'presenca', (select coalesce(jsonb_agg(jsonb_build_object(
           'name', p.nome, 'u10', p.u10, 'anual', p.anual,
           'dates', (select jsonb_agg(s.presenca order by s.idx) from serie s where s.nome = p.nome))
         order by p.u10 desc, p.anual desc, p.nome), '[]'::jsonb) from pres p)
);
$$;
revoke execute on function public._tabelas(date) from public, anon, authenticated;

-- posição (1, 2, 3...) de cada nome numa lista ordenada
create or replace function public._posicoes(p_lista jsonb)
returns jsonb language sql immutable set search_path = '' as $$
  select coalesce(jsonb_object_agg(e->>'name', ord), '{}'::jsonb)
  from jsonb_array_elements(coalesce(p_lista, '[]'::jsonb)) with ordinality as t(e, ord);
$$;
revoke execute on function public._posicoes(jsonb) from public, anon, authenticated;

create or replace function public.get_dados()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_atual jsonb;
  v_ant   jsonb;
  v_data_ant date;
  v_out   jsonb;
begin
  v_atual := public._tabelas('infinity'::date);
  select data into v_data_ant from public.peladas where status = 'encerrada'
   order by data desc offset 1 limit 1;
  if v_data_ant is not null then
    v_ant := public._tabelas(v_data_ant);
  end if;

  with enc as (
    select id, data from public.peladas where status = 'encerrada'
  ),
  res_dates as (
    select e.id, e.data, row_number() over (order by e.data) as idx
    from enc e
    where exists (select 1 from public.participacoes x where x.pelada_id = e.id and x.resultado is not null)
  ),
  pa as (
    select x.*, j.nome from public.participacoes x
    join enc e on e.id = x.pelada_id join public.jogadores j on j.id = x.jogador_id
  )
  select jsonb_build_object(
    'ok', true,
    'rankingData',      v_atual->'ranking',
    'artilhariaData',   v_atual->'artilharia',
    'assistenciasData', v_atual->'assistencias',
    'presencaData',     v_atual->'presenca',
    'posAnterior', case when v_ant is null then null else jsonb_build_object(
        'ranking',      public._posicoes(v_ant->'ranking'),
        'artilharia',   public._posicoes(v_ant->'artilharia'),
        'assistencias', public._posicoes(v_ant->'assistencias'),
        'presenca',     public._posicoes(v_ant->'presenca')) end,
    'totalPeladas',     (select count(*) from res_dates),
    'datasPeladas',     coalesce((select jsonb_agg(to_char(data,'DD/MM') order by idx) from res_dates), '[]'::jsonb),
    'historicoPeladas', coalesce((select jsonb_agg(jsonb_build_object(
        'data', to_char(r.data, 'DD/MM/YYYY'),
        'jogadores', coalesce((select jsonb_agg(jsonb_build_object('name', x.nome, 'res', x.resultado) order by x.nome)
                               from pa x where x.pelada_id = r.id and x.resultado is not null), '[]'::jsonb),
        'gols',      coalesce((select jsonb_object_agg(x.nome, x.gols) from pa x where x.pelada_id = r.id and x.gols > 0), '{}'::jsonb),
        'assists',   coalesce((select jsonb_object_agg(x.nome, x.assists) from pa x where x.pelada_id = r.id and x.assists > 0), '{}'::jsonb)
      ) order by r.idx) from res_dates r), '[]'::jsonb),
    'goleiroStats', coalesce((select jsonb_object_agg(goleiro, o) from (
        select g.goleiro, jsonb_build_object(
          'gols_tomados', sum(g.gols_tomados), 'vitorias', sum(g.vitorias), 'derrotas', sum(g.derrotas),
          'porData', jsonb_object_agg(to_char(e.data,'DD/MM'), jsonb_build_object(
              'gols_tomados', g.gols_tomados, 'vitorias', g.vitorias, 'derrotas', g.derrotas))) as o
        from public.goleiros_dia g join enc e on e.id = g.pelada_id
        group by g.goleiro) q), '{}'::jsonb),
    'jogadores', coalesce((select jsonb_agg(nome order by nome) from public.jogadores), '[]'::jsonb)
  ) into v_out;
  return v_out;
end $$;
grant execute on function public.get_dados() to anon, authenticated;
