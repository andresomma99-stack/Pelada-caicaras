# Pelada de Quinta ⚽

Site de estatísticas da pelada dos Caiçaras: classificação, artilharia, assistências,
presença, histórico, destaques, goleiros e a aba **Ao Vivo**, compartilhada em tempo real
entre todos os celulares.

## Como funciona

| Peça | Onde | Custo |
|---|---|---|
| Site (`index.html`) | Vercel, deploy automático a cada push no `main` | grátis (Hobby) |
| Banco de dados | Supabase (`pelada-caicaras`, São Paulo) | grátis |
| Keep-alive | GitHub Actions, a cada 3 dias (`.github/workflows/keepalive.yml`) | grátis |
| Backup | GitHub Actions, toda segunda → branch `backups` | grátis |

## Banco

Tudo é computado **por dia**: cada quinta é uma linha em `peladas`, e cada jogador
naquele dia é uma linha em `participacoes` (time, V/E/D, gols, assistências, presença).

- `get_dados()` monta as tabelas do site.
- A aba Ao Vivo guarda o estado em `peladas.estado` (com controle de versão) e cada gol ou
  assistência em `eventos`. "Desfazer" só marca o evento como anulado.
- `encerrar_pelada()` grava o dia inteiro de uma vez.
- Ninguém escreve nas tabelas diretamente: só por essas funções.

Migrações em `supabase/migrations/`.

## Se o banco for pausado

O keep-alive evita isso. Se acontecer mesmo assim, entre em supabase.com → projeto
`pelada-caicaras` → **Restore**. Os dados não se perdem.

## Restaurar um backup

Os arquivos ficam em `backups/AAAA-MM-DD/` no branch `backups` (um JSON por tabela).
