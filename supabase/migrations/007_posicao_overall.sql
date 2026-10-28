-- Posição em que cada jogador foi escalado no dia (ZAG/LAT/MEI/ATA).
-- Usada pelo overall do card do jogador: o peso dos atributos depende da posição.
-- A posição vem da escalação da aba Ao Vivo (peladas.estado -> teams -> cor -> slot),
-- gravada automaticamente quando a pelada é encerrada (gatilho abaixo), sem
-- depender da versão do site que encerrou.

alter table public.participacoes
  add column if not exists posicao text check (posicao in ('ZAG','LAT','MEI','ATA'));

create or replace function public._gravar_posicoes()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'encerrada' and old.status is distinct from 'encerrada' and new.estado ? 'teams' then
    update public.participacoes x
       set posicao = s.pos
      from (
        select distinct on (j.id) j.id as jogador_id,
               case when slot.key = 'zag' then 'ZAG'
                    when slot.key like 'lat%' then 'LAT'
                    when slot.key like 'mei%' then 'MEI'
                    when slot.key = 'ata' then 'ATA' end as pos
        from jsonb_each(new.estado->'teams') cor
        cross join lateral jsonb_each_text(case when jsonb_typeof(cor.value) = 'object' then cor.value else '{}'::jsonb end) slot
        join public.jogadores j on j.nome = trim(slot.value)
        where slot.key in ('zag','lat1','lat2','mei1','mei2','ata') and length(trim(slot.value)) > 0
        order by j.id, slot.key
      ) s
     where x.pelada_id = new.id and x.jogador_id = s.jogador_id and s.pos is not null;
  end if;
  return new;
end $$;
revoke execute on function public._gravar_posicoes() from public, anon, authenticated;

drop trigger if exists peladas_gravar_posicoes on public.peladas;
create trigger peladas_gravar_posicoes
  after update of status on public.peladas
  for each row execute function public._gravar_posicoes();

-- get_dados: igual à 005, com a posição de cada jogador no histórico ('pos')
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
        'jogadores', coalesce((select jsonb_agg(jsonb_build_object('name', x.nome, 'res', x.resultado, 'pos', x.posicao) order by x.nome)
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
