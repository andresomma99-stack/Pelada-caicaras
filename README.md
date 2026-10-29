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
- **Importar times por foto** (Ao Vivo): o print é lido no próprio celular (Tesseract.js); a cor do
  rótulo "TIME X" define o time. Nomes em dúvida são confirmados num pop-up e o vínculo vira um
  apelido em `apelidos` (`get_apelidos()` / `salvar_apelidos()`), reconhecido automaticamente depois.
- **Posição do dia**: ao encerrar a pelada, um gatilho (`_gravar_posicoes`) copia a escalação do Ao Vivo
  (`peladas.estado.teams`) para `participacoes.posicao` (ZAG/LAT/MEI/ATA).
- **Overall (card do jogador)**: calculado no site a partir de `historicoPeladas`, começando na primeira pelada com
  posições gravadas. 6 atributos (RES, ATA, SEG, FOR, ASS, EXP) com pesos por posição (ATA/MEI × ZAG/LAT); ATA compara
  G+A com a média da posição; SEG usa os gols sofridos pelo time por partida (placares de `peladas.estado.matchHistory`,
  devolvidos por `get_dados` em `partidas` — migração 009) e, depois de 10 peladas com placar, desconta o efeito do
  goleiro. Faltas só reduzem a assiduidade. Provisório até 5 peladas jogadas. Pesos em `OVR_CFG` no `index.html`.
- **Jogador da semana (POTW)**: nota do dia (0–10) de cada pelada com posição, calculada no site
  (`NOTA_CFG`): resultado (×1,43 para ZAG/LAT) + gols/assistências com retorno decrescente.
  O vencedor ganha a coroa na Classificação até a próxima pelada; a lista fica na aba POTW.
  `get_dados` devolve o `time` de cada jogador (migração 008) para a imagem de resultado.
- Ninguém escreve nas tabelas diretamente: só por essas funções.

Migrações em `supabase/migrations/`.

## Se o banco for pausado

O keep-alive evita isso. Se acontecer mesmo assim, entre em supabase.com → projeto
`pelada-caicaras` → **Restore**. Os dados não se perdem.

## Restaurar um backup

Os arquivos ficam em `backups/AAAA-MM-DD/` no branch `backups` (um JSON por tabela).
