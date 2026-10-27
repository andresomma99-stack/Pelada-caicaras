-- Pelada de Quinta — schema
-- Tudo é computado por DIA (tabela peladas = uma quinta). Leitura pública,
-- escrita somente por funções controladas (security definer).

create table public.jogadores (
  id            bigint generated always as identity primary key,
  nome          text not null unique check (length(trim(nome)) > 0),
  ajuste_pontos int  not null default 0,   -- bônus manuais herdados da planilha (não entram na pontuação do site)
  criado_em     timestamptz not null default now()
);

create table public.peladas (
  id           bigint generated always as identity primary key,
  data         date not null,
  status       text not null default 'encerrada'
               check (status in ('ao_vivo','encerrada','descartada')),
  estado       jsonb,                 -- estado compartilhado da aba Ao Vivo
  versao       int  not null default 0,
  criado_em    timestamptz not null default now(),
  encerrada_em timestamptz
);
-- uma pelada válida por dia (descartadas liberam a data)
create unique index peladas_data_unica on public.peladas (data) where status <> 'descartada';
-- no máximo uma pelada ao vivo por vez
create unique index peladas_um_ao_vivo on public.peladas ((true)) where status = 'ao_vivo';

create table public.participacoes (
  pelada_id  bigint not null references public.peladas(id) on delete cascade,
  jogador_id bigint not null references public.jogadores(id),
  time       text check (time in ('red','yellow','blue')),
  resultado  text check (resultado in ('V','E','D')),
  gols       int  not null default 0,
  assists    int  not null default 0,
  presenca   numeric(4,1),
  primary key (pelada_id, jogador_id)
);
create index participacoes_jogador on public.participacoes (jogador_id);

create table public.goleiros_dia (
  pelada_id    bigint not null references public.peladas(id) on delete cascade,
  goleiro      text not null,
  gols_tomados int not null default 0,
  vitorias     int not null default 0,
  derrotas     int not null default 0,
  primary key (pelada_id, goleiro)
);

-- eventos do Ao Vivo (gols/assistências). Nunca apagados: "desfazer" marca anulado.
create table public.eventos (
  id         bigint generated always as identity primary key,
  pelada_id  bigint not null references public.peladas(id) on delete cascade,
  client_id  uuid   not null unique,        -- idempotência (reenvio offline)
  partida    int    not null,
  tipo       text   not null check (tipo in ('gol','assist')),
  jogador    text   not null,
  time       text   not null check (time in ('red','yellow','blue')),
  minuto     int    not null default 1,
  anulado    boolean not null default false,
  aparelho   text,
  criado_em  timestamptz not null default now(),
  anulado_em timestamptz
);
create index eventos_pelada on public.eventos (pelada_id);

-- log de alterações de estado (auditoria / desfazer manual)
create table public.log_estado (
  id        bigint generated always as identity primary key,
  pelada_id bigint not null references public.peladas(id) on delete cascade,
  versao    int not null,
  acao      text,
  aparelho  text,
  estado    jsonb,
  criado_em timestamptz not null default now()
);

-- RLS: todos leem, ninguém escreve direto
alter table public.jogadores     enable row level security;
alter table public.peladas       enable row level security;
alter table public.participacoes enable row level security;
alter table public.goleiros_dia  enable row level security;
alter table public.eventos       enable row level security;
alter table public.log_estado    enable row level security;

create policy leitura on public.jogadores     for select to anon, authenticated using (true);
create policy leitura on public.peladas       for select to anon, authenticated using (true);
create policy leitura on public.participacoes for select to anon, authenticated using (true);
create policy leitura on public.goleiros_dia  for select to anon, authenticated using (true);
create policy leitura on public.eventos       for select to anon, authenticated using (true);

revoke insert, update, delete, truncate on all tables in schema public from anon, authenticated;

-- tempo real para a aba Ao Vivo
alter publication supabase_realtime add table public.peladas, public.eventos;
