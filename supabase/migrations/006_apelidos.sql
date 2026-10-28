-- Apelidos lidos por foto (importação de times no Ao Vivo).
-- Quando alguém liga manualmente um nome lido no print a um jogador cadastrado,
-- o vínculo fica salvo aqui e da próxima vez é reconhecido automaticamente.
-- "apelido" é guardado já normalizado pelo site (minúsculo, sem acento, sem símbolos).

create table public.apelidos (
  apelido    text   primary key check (length(apelido) between 1 and 40 and apelido ~ '^[a-z0-9 ]+$'),
  jogador_id bigint not null references public.jogadores(id) on delete cascade,
  criado_em  timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

alter table public.apelidos enable row level security;
create policy leitura on public.apelidos for select to anon, authenticated using (true);
revoke insert, update, delete, truncate on public.apelidos from anon, authenticated;

create or replace function public.get_apelidos()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('apelido', a.apelido, 'jogador', j.nome) order by a.apelido), '[]'::jsonb)
  from public.apelidos a join public.jogadores j on j.id = a.jogador_id;
$$;

-- p_lista: [{"apelido": "pp", "jogador": "Nome Cadastrado"}, ...]
create or replace function public.salvar_apelidos(p_lista jsonb)
returns int language plpgsql security definer set search_path = '' as $$
declare
  it jsonb;
  v_apelido text;
  v_jog bigint;
  n int := 0;
begin
  if p_lista is null or jsonb_typeof(p_lista) <> 'array' or jsonb_array_length(p_lista) > 40 then
    raise exception 'lista_invalida';
  end if;
  for it in select * from jsonb_array_elements(p_lista) loop
    v_apelido := lower(trim(it->>'apelido'));
    if v_apelido is null or length(v_apelido) = 0 or length(v_apelido) > 40 or v_apelido !~ '^[a-z0-9 ]+$' then
      continue;
    end if;
    select id into v_jog from public.jogadores where nome = it->>'jogador';
    if v_jog is null then continue; end if;
    insert into public.apelidos (apelido, jogador_id) values (v_apelido, v_jog)
      on conflict (apelido) do update set jogador_id = excluded.jogador_id, atualizado_em = now();
    n := n + 1;
  end loop;
  return n;
end $$;

grant execute on function public.get_apelidos(), public.salvar_apelidos(jsonb) to anon, authenticated;
