# ADM-projetos — AGENTS.md (Referência Canônica)

> Documento de referência para IA e desenvolvedores.  
> Toda alteração no app deve manter este arquivo atualizado.

---

## ⚠️ REGRA DE OURO — NUNCA APAGAR O CONTEÚDO DO USUÁRIO

> **Ao criar QUALQUER nova versão (V0.1.x), a IA deve garantir que o update
> não apague nem sobrescreva o conteúdo que o usuário escreveu no app.**

Checklist OBRIGATÓRIO antes de publicar uma versão nova:

1. **Não mexer nos dados sem proteção** — qualquer mudança em
   `Storage`/`models`/fluxo de leitura/escrita deve manter (ou reforçar) a
   cadeia de proteção do V0.1.45:
   - Snapshot por versão (`adm_projetos.json.v<versao>` antes de qualquer
     leitura/escrita quando a versão muda);
   - `.bak` da versão anterior antes de cada gravação;
   - Guarda anti-esvaziamento (gravação com lista VAZIA nunca sobrescreve um
     arquivo com conteúdo, exceto exclusão explícita do último projeto via
     `liberarEsvaziamento()`);
   - Reparo automático de JSON danificado + cópia `.corrompido` + restauração
     da cadeia principal → `.bak` → snapshots.
2. **Nunca chamar `Storage.substituir()` sem necessidade** (importar backup e
   "Baixar da nuvem" são os únicos lugares legítimos, ambos com confirmação).
3. **Nunca escrever uma lista vazia por cima de dados existentes** (a guarda
   do `_gravar` bloqueia; não remover nem contornar).
4. **Testes de regressão de dados** — `flutter test` deve passar com o
   `test/backup_test.dart` (11 testes que cobrem .bak, snapshots, reparo,
   guarda anti-esvaziamento). NÃO remover esses testes ao refatorar.
5. **Bump de versão** — sempre incrementar `appVersao` (`lib/versao.dart`) e
   `version:` (`pubspec.yaml`) ao publicar (fluxo na seção 12).

> Histórico do incidente que originou esta regra: um usuário perdeu todo o
> conteúdo após atualizar o app — o arquivo de dados foi sobrescrito em algum
> momento entre versões. As proteções da V0.1.42–45 existem para que isso
> nunca mais aconteça; respeitá-las é obrigatório.

---

## 1. Visão Geral

App Android (Flutter) para **anotar ideias** em projetos, com listas numeradas, checkboxes, links, comentários, temas e backup.

- **Nome do app (exibido):** Taskix (título ao lado do logo na tela inicial,
  rótulo do launcher `android:label`, e `MaterialApp.title`). O código/pacote
  ainda usa o identificador antigo `adm_projetos` (não renomeado — só o nome
  visível mudou de "ADM-projetos" para "Taskix" na V0.1.42).
- **Pacote Android:** `com.admprojetos.adm_projetos`
- **Flutter:** 3.44.7 (stable) — `pubspec.yaml`: SDK `^3.12.2`
- **Repositório:** `viniciostristao1/adm-projetos` (PÚBLICO — repositórios
  públicos têm minutos de GitHub Actions ilimitados; o CI publica o APK na
  release `v0.1.0`)
- **Release APK:** `https://github.com/viniciostristao1/adm-projetos/releases/tag/v0.1.0`

---

## 2. Estrutura de Arquivos (apenas `lib/`)

```
lib/
├── main.dart            # Entry point + temas (Azul/Escuro/Dark Game/Bege)
├── models.dart          # Nota, Projeto — serialização JSON
├── storage.dart         # Persistência local (singleton Storage) + exportarJson/substituir + recentes (últimos abertos) + backup .bak
├── tema.dart            # TemaController (ChangeNotifier) + enums Modo, ModoFonte e Densidade (Confortável/Compacto)
├── cores.dart           # AppCores (ThemeExtension) — 8 cores/tema
├── projetos_screen.dart # Tela principal: lista de projetos + busca + backup (export/import)
├── projeto_screen.dart  # Tela de 1 projeto: abas Tarefas/Ideias + _CaixaNota
├── pdf_export.dart      # Gera PDF do projeto inteiro e compartilha (printing)
├── ocr.dart             # extrairTextoDeImagem(): galeria + ML Kit (OCR local)
├── editor.dart          # Utilitários: copiarTexto, mostrarAviso(Acao), capitalizarInicial,
│                        #   proximoNumeroLista, LinhasNumeradas, maiusculaAposItem,
│                        #   HistoricoTexto (undo), BuscaController (destaque de busca)
├── barra_config.dart    # enum Ferramenta + BarraController (ORDEM dos botões da barra da
│                        #   caixinha, persistida) + OrdemBarraScreen (tela de reordenar)
├── caixa3d.dart         # Widget simples: Container com cor sólida + borderRadius
├── sync_service.dart    # SyncService (Firebase Firestore) — nuvem 100% MANUAL (por botão)
├── lembretes.dart       # LembretesService (flutter_local_notifications) — lembretes rápidos
│                        #   com notificação local do Android (item 5, V0.1.54)
└── versao.dart          # const appVersao (exibida no topo; bump a cada release)
```

---

## 3. Modelos de Dados

### Nota (`models.dart`)
| Campo | Tipo | JSON key |
|---|---|---|
| `id` | `String` | `id` |
| `texto` | `String` | `texto` |
| `concluida` | `bool` | `concluida` |
| `comentario` | `String?` | `comentario` (omisso se null) |
| `links` | `List<NotaLink>` | `links` (`url` + `titulo` opcional — título do YouTube) |

### Projeto (`models.dart`)
| Campo | Tipo | JSON key |
|---|---|---|
| `id` | `String` | `id` |
| `nome` | `String` | `nome` |
| `tarefas` | `List<Nota>` | `tarefas` |
| `futuro` | `List<Nota>` | `futuro` |
| `emAndamento` | `bool` | `emAndamento` (✓ verde no cartão da lista) |

> **Backward compat:** `fromJson` migra chave antiga `notas` → `tarefas`.

---

## 4. Sistema de Temas

### Modo (enum em `tema.dart`)
`azul`, `escuro`, `neumB` (Dark Game), `bege`, `claude` (Claude Code) —
**5 temas** (estilo inspirado no app Calis Timer: azul = navy plano com accent
azul; bege = claro com as cores do tema madeira — tons amadeirados com accent
laranja-marrom). Bege é o único claro (roda em `ThemeMode.light`); os demais
são escuros. `claude` é o tema terminal (Claude Code): preto-quente #0C0C0D,
superfícies #161617 com borda de 1px #2A2A2B, acento terracota #D97757 e fonte
monoespaçada JetBrains Mono (sem sombras).

- `themeFlutter`: light para `bege`; dark para os demais.
- Seletor de tema na engrenagem: `ChoiceChip` para cada `Modo` (usa `Modo.rotulo`).
- **Migração de temas antigos** (`TemaController.carregar`): `claro` → `azul`;
  `espresso`/`bege`/`begeNeum` → `bege`; padrão (sem preferência) = `azul`.

### Claude Code (claude)
- Plano (sem sombras, `neumorfico: false`): cartões com borda de 1px
  `#2A2A2B`, cantos 10px, FAB terracota `#D97757` com ícone escuro.
- Fonte **JetBrains Mono** (Regular/Medium/Bold, assets locais) aplicada via
  `ThemeData.fontFamily` em `_temaClaude()` — vale para todo o app (a caixinha
  herda via `_estiloCampo`, que usa `textTheme.bodyMedium.fontFamily`).
- `projetoScreen`: no tema Claude o cartão de projeto vira "linha" — borda
  de 1px, e o projeto em andamento ganha uma **barra terracota de 3px à
  esquerda** com o "v" terracota (em vez de verde); bolinhas invisíveis com
  ícones apagados (alpha 0.45); nome em mono.
- Barra de ferramentas da caixinha no Claude: tom intermediário
  (`barraFerramentas` `#111213`) entre a caixinha (`#161617`) e o fundo
  (`#0C0C0D`).

### Dark Neumorphism (neumB)
- `AppCores.neumorfico == true` habilita superfícies em relevo (luz ↗ superior
  esquerda, sombra dupla difusa, SEM linhas/bordas — o highlight vem do brilho
  difuso).
- `Caixa3D` renderiza gradiente (`notaInicio`→`notaFim`, ou `corInicio`/
  `corFim` quando passados — ex.: cartões de projeto usam `projetoCard`→
  `projetoCardFim`); as cores das sombras/luz vêm de `sombraForte`,
  `sombraFraca`, `brilho` e `bordaLuz` (por paleta).
- Barra de ferramentas: usa gradiente próprio (`barraFerramentas`→
  `barraFerramentasFim`) quando difere da superfície;
  senão segue o gradiente da superfície.
- `BotaoNeum` (caixa3d.dart): botão interativo com estado pressionado (inset
  simulado por gradiente) e `selecionado` (tint do acento).
- `Fundo` (caixa3d.dart): gradiente radial (`fundoInicio`→`fundoFim`) aplicado
  POR TELA, dentro da rota — durante o gesto de voltar, o fundo participa do
  fade junto com o conteúdo (evita efeito "fantasma" da rota anterior).
- Fonte: **Manrope** (variável, asset local) — só nos temas neumórficos.
- FAB: cor `fab` (acento) com elevação 8; abas com indicador "pill" do acento.
- Texto da interface (títulos/abas/chips): `textoUI` — separado de
  `projetoTxt` (texto DENTRO dos cartões) para os temas em que o cartão tem
  cor própria.

### AppCores (ThemeExtension em `cores.dart`)
8 campos de cor por tema + 3 novos:

| Campo | Uso |
|---|---|
| `notaInicio` | Cor inicial da superfície (A/B: gradiente topo-esquerda) |
| `notaFim` | Cor final da superfície (A/B: gradiente baixo-direita) |
| `notaBorda` | Borda da caixinha (não usada no layout) |
| `projetoCard` | Fundo do cartão de projeto na lista principal |
| `projetoTxt` | Cor do texto no cartão de projeto |
| `fab` | Cor de fundo do FAB (botão `+`) |
| `fabIcone` | Cor do ícone no FAB |
| `barraFerramentas` | Cor da barra de ícones no topo de cada caixinha |
| `neumorfico` | bool — ativa relevo neumórfico (Dark Game) |
| `fundoInicio` / `fundoFim` | Gradiente do fundo do app |
| `sombraForte` / `sombraFraca` | Sombras duplas difusas (cores por tema) |
| `brilho` | Luz refletida no canto superior esquerdo |
| `bordaLuz` | Highlight de 1px (topo/esquerda) |
| `projetoCardFim` | Ponta escura do gradiente do cartão de projeto |
| `barraFerramentasFim` | Ponta escura do gradiente da barra de ferramentas |
| `textoUI` | Texto da interface (títulos, abas, chips) |

### Valores por tema

**Azul** (plano, estilo Calis Timer — navy + accent azul):
| Campo | Hex |
|---|---|
| `notaInicio` / `notaFim` | `#121A2E` / `#1B2540` |
| `notaBorda` | `#14FFFFFF` |
| `projetoCard` / `projetoCardFim` | `#121A2E` / `#0A0F1C` |
| `projetoTxt` | `#EAF0FB` |
| `fab` / `fabIcone` | `#3B82F6` / `#F2F7FF` |
| `barraFerramentas` / `barraFerramentasFim` | `#1B2540` / `#121A2E` |
| `fundoInicio` / `fundoFim` | `#0A0F1C` / `#070B14` |
| `textoUI` | `#EAF0FB` |

**Escuro:**
| Campo | Hex |
|---|---|
| `notaInicio` / `notaFim` | `#252525` / `#252525` |
| `notaBorda` | `#33FFFFFF` |
| `projetoCard` | `#000000` |
| `projetoTxt` | `#FFFFFF` |
| `fab` / `fabIcone` | `#D48000` / `#1A0E00` |
| `barraFerramentas` | `#1A1A1A` |

**Dark Game (neumB)** — neumórfico:
| Campo | Hex |
|---|---|
| `notaInicio` / `notaFim` | `#1B1D20` / `#111315` |
| `projetoCard` / `projetoCardFim` | `#1B1D20` / `#111315` |
| `projetoTxt` | `#EDEFF1` |
| `fab` / `fabIcone` | `#9AA4AE` / `#0D1012` |
| `barraFerramentas` / `barraFerramentasFim` | `#111315` / `#111315` |
| `fundoInicio` / `fundoFim` | `#121517` / `#0A0C0D` |
| sombras | `sombraForte #C0000000`, `sombraFraca #80000000`, `brilho #08FFFFFF`, `bordaLuz #10FFFFFF` |
| `textoUI` | `#EDEFF1` |

**Bege** — plano, estilo Calis Timer (madeira claro + accent laranja).
As PASTAS de projeto usam `projetoCard` = `#E0D1B9`, a MESMA cor das
caixinhas (os temas planos renderizam o cartão do projeto com essa cor):
| Campo | Hex |
|---|---|
| `notaInicio` / `notaFim` | `#E0D1B9` / `#CBB897` |
| `notaBorda` | `#14000000` |
| `projetoCard` / `projetoCardFim` | `#E0D1B9` / `#D8C7AC` |
| `projetoTxt` | `#382E20` |
| `fab` / `fabIcone` | `#B5652E` / `#FFF3E7` |
| `barraFerramentas` / `barraFerramentasFim` | `#CBB897` / `#CBB897` |
| `fundoInicio` / `fundoFim` | `#F2E8D6` / `#EADFC8` |
| `textoUI` | `#382E20` |

**Claude Code** — plano, estilo terminal (preto-quente + terracota + mono):
| Campo | Hex |
|---|---|
| `notaInicio` / `notaFim` | `#1E1E20` / `#1E1E20` (interior da caixinha — clareado na V0.1.42, era `#161617`) |
| `notaBorda` | `#FF2A2A2B` (borda de 1px dos cartões) |
| `projetoCard` / `projetoCardFim` | `#161617` / `#161617` (cartão de projeto na tela inicial — NÃO clareado) |
| `projetoTxt` | `#F0EEE9` |
| `fab` / `fabIcone` | `#D97757` / `#120806` |
| `barraFerramentas` / `barraFerramentasFim` | `#18181A` / `#18181A` (barra da caixinha — clareada na V0.1.42, era `#111213`) |
| `fundoInicio` / `fundoFim` | `#0C0C0D` / `#0C0C0D` |
| `textoUI` | `#F0EEE9` |

> **V0.1.42:** a pedido do usuário, o interior da caixinha e a barra de
> ferramentas ficaram "um pouquinho mais claros", cada um em separado,
> mantendo a hierarquia: barra (`#18181A`) mais escura que o interior
> (`#1E1E20`), e o fundo (`#0C0C0D`) o mais escuro de todos. Só no tema Claude.

- **Cartão de projeto (linha):** borda 1px `#2A2A2B` (usa `notaBorda`), cantos
  10px; em andamento = barra esquerda de 3px `#D97757` + "v" terracota
  (`corCheckAndamento = app.fab`); bolinhas invisíveis, ícones com alpha 0.45.
- **Barra superior:** fundo `#0C0C0D` igual ao da página; tabs com label
  terracota.

- **Barra superior** (página principal e projeto) no Bege: `#E0D1B9` (a
  mesma cor do interior das caixinhas) — `appBarColor` no `_temaClaroCalis`.
- **Fundo do Bege** (página principal e dentro do projeto): bege CLARO
  `#F2E8D6` — pastas e caixinhas (`#E0D1B9`) ficam escuras sobre ele.
- **Check "em andamento" das pastas** no Bege: bolinha PRETA com "v" bege
  (`app.notaInicio`) quando marcado, igual ao quadradinho dentro das
  caixinhas.

---

## 5. Fluxo de Telas

```
ProjetosScreen (lista de projetos)
  ├─ FAB [+] → criar projeto
  ├─ 🔔 (à ESQUERDA da lupa) → folha "Lembrete rápido": escrever + tocar num
  │       tempo (30 min · 2 h · 4 h · 24 h · Outro…) agenda uma NOTIFICAÇÃO
  │       local do Android; lista os agendados com X p/ cancelar (item 5,
  │       V0.1.54). Detalhe em §6 "Lembretes".
  ├─ 🔍 → busca GLOBAL (projetos por nome + conteúdo das caixinhas em
  │       Tarefas/Ideias); tocar num resultado abre a caixinha
  ├─ "RECENTES" → prateleira rolante horizontal com os 5 projetos
  │    mais recentemente abertos (nome + contagem de caixinhas + barra de
  │    progresso feitas/total); tocar abre o projeto. Na MESMA LINHA do
  │    rótulo, no canto direito: ÍCONE de nuvem com flecha p/ cima + data do
  │    último envio (V0.1.50; terracota no Claude; "nunca" se nunca enviou)
  │    (SyncService.ultimoEnvio, persistida — "nunca enviado" se nunca)
  ├─ SEÇÕES (V0.1.46): com ≥1 projeto em andamento, a lista vira
  │    "EM ANDAMENTO · N" (acento) + "OUTROS · N"; arrastar só move DENTRO
  │    da seção (_reordenarComSecoes)
  ├─ Card → ProjetoScreen (projeto aberto)
  │    ├─ Tab "Tarefas" → ReorderableListView de _CaixaNota
  │    ├─ Tab "Ideias" → idem
  │    ├─ 🔍 (ao lado das abas) → busca na aba ativa (texto + comentário)
  │    │     — o termo buscado fica GRIFADO (marcador amarelo) nas caixinhas
  │    ├─ ✔ caixinha marcada/desmarcada como feita → ESPELHA o projeto:
  │    │     marcou = "em andamento"; desmarcou = sai do andamento.
  │    │     E o inverso: DESMARCAR no cartão do projeto desmarca as
  │    │     caixinhas feitas lá dentro (V0.1.47/49/50)
  │    └─ PDF → gera PDF do projeto inteiro e compartilha
  └─ ⚙️ → ConfigSheet (V0.1.51: seções EXPANSÍVEIS — toca na seção e ela
       abre com as opções; cada uma mostra o valor atual no subtítulo: Tema,
       Tamanho da fonte, Densidade, Barra de ferramentas, Backup, Nuvem;
       V0.1.52: NENHUMA seção abre sozinha — a Tema, que ficava aberta, agora
       também nasce fechada; V0.1.54: a folha abre com `isScrollControlled` e
       até 90% da altura da tela — antes ficava baixa e a seção Nuvem, ao
       expandir, caía fora do visível e a rolagem apertava)
```

> **Densidade (V0.1.46):** `Densidade` (Confortável/Compacto) no `TemaController`
> (SharedPreferences `densidade_v1`). Compacto aproxima: cartões da lista
> (bottom 5 vs 10), cabeçalhos, prateleira RECENTES (altura 58 vs 72) e as
> caixinhas do projeto (bottom 5 vs 10, padding inferior da lista menor).
> Seletor nas Configurações (SegmentedButton).

> **ConfigSheet fecha arrastando para baixo (V0.1.42):** o
> `showModalBottomSheet` usa `showDragHandle: true` — a alça no topo virou um
> alvo de arraste CONFIÁVEL. Antes o `SingleChildScrollView` do conteúdo
> engolia o gesto e só dava para sair pelo botão "voltar" do Android. A alça
> decorativa manual foi removida (agora vem do próprio showDragHandle).

### Prateleira "Últimos abertos" (página principal)
- Mostra os `Storage.maxRecentes` (5) projetos mais recentemente abertos, em
  cartões compactos roláveis na horizontal, com contagem de caixinhas e barra
  de progresso (`feitas/total`, preenchimento na cor `fab`).
- Rastreio em `Storage` via SharedPreferences (chave `recentes_v1`):
  `registrarAbertura(id)` (move pro topo, máx. 3), `recentesIds()`,
  `removerRecente(id)` (ao excluir a pasta; "Desfazer" re-registra).
- `_recarregarRecentes()` remonta a lista a partir dos IDs (só projetos que
  ainda existem) — chamado ao abrir a tela, ao voltar de um projeto, após
  "Baixar da nuvem" e após excluir/desfazer.
- Some durante a busca (campo `🔍` aberto). No tema Claude, os cartões usam
  borda de 1px `#2A2A2B`; em temas neumórficos usa `Caixa3D`.

### Barra de ferramentas da caixinha (`_CaixaNota`)

Barra com rolagem horizontal (o pino de arrastar fica fixo à esquerda). A
**ORDEM dos botões é configurável** pelo usuário (Configurações → "Barra de
ferramentas das caixinhas" → "Mudar ordem dos botões", que abre a
`OrdemBarraScreen`) e vale para TODAS as caixinhas. A ordem é guardada por
`BarraController` (SharedPreferences `barra_ordem_v1`); a barra se reconstrói
via `ListenableBuilder(listenable: barraController)`. Cada botão é desenhado
por `_botaoFerramenta(Ferramenta, onBarra)` — a `Ferramenta.numerar` só existe
na aba Tarefas (retorna null nas Ideias). Ferramentas novas entram no FIM da
ordem salva de quem já usava o app. Ordem PADRÃO (esquerda→direita, após o pino):

1. `copy_all_outlined` (copiar — botão mais usado, vem primeiro)
2. `undo` (desfazer apagar — volta o texto apagado de uma vez)
3. `check_box` / `check_box_outline_blank` (to-do da caixinha: marcar como feito)
4. `format_list_numbered` / `format_align_justify` (numeração — **só em Tarefas**)
5. `checklist` (inserir item de to-do "☐ ")
6. `arrow_downward` / `arrow_upward` (mover para a outra aba)
7. `unfold_more` (topo/pé do texto)
8. `add_link` (link — até 3, cada um com título de vídeo)
9. `image_outlined` (Ler texto de imagem — OCR, insere na posição do cursor)
10. `chat_bubble` / `chat_bubble_outline` (comentário inline)
11. `edit_outlined` (focar no fim)
12. `format_align_center` (centralizar a LINHA da seleção — insere espaços
    no início calculados pela largura real do texto, pois o TextField não
    suporta alinhamento por linha; a palavra fica centralizada NA MESMA
    linha; desfazer reverte; sem seleção mostra aviso)
13. `cleaning_services` (limpar)
14. `delete_outline` (excluir, vermelho)

---

## 6. Comportamentos Específicos

### Lista numerada
- **Tarefas:** ao pressionar Enter, se a linha anterior é numerada, insere `"N- "` automaticamente.
- O botão de numeração **alterna o número da linha do cursor**: remove o `"N- "` se existir, ou adiciona o próximo número. Não insere linhas novas (quem cria linha é o Enter).
- **Ideias:** sem numeração automática, sem botão de lista.
- Nova caixinha em Tarefas inicia com `"1- "`; Ideias inicia vazio.

### Itens de to-do (quadradinhos ☐/☑)
- Botão `checklist` **converte a LINHA DO CURSOR** em item de to-do (ou remove
  o quadradinho se a linha já for um item) — funciona em qualquer linha, como
  o botão de numeração. Não cria mais linha no fim do texto.
- ⚠️ **`_linhaDoCursor` fica EXATAMENTE na linha do cursor (V0.1.42)**, mesmo
  que ela esteja vazia. Antes havia um "recuo" que voltava para a última linha
  COM conteúdo quando a linha do cursor era vazia — isso quebrava criar um
  to-do (ou numerar) numa 2ª linha em branco: o marcador ia parar na 1ª linha
  e o cursor também (bug relatado). Vale para `_inserirTodo` e `_alternarNumero`.
- O Enter continua com `"☐ "` nas linhas seguintes (via `LinhasNumeradas`) —
  inclusive depois de uma linha JÁ MARCADA (`☑`), para o checkbox da próxima
  linha sempre nascer desmarcado.
- Os quadradinhos usam `\uFE0E` (VS15) para forçar a apresentação em TEXTO —
  sem isso alguns celulares desenham ☐/☑ como emoji colorido. O VS15 é
  garantido em 3 pontos: ao converter com o botão `checklist`, ao tocar no
  quadradinho (`_toqueTexto` sempre grava `☑\uFE0E`/`☐\uFE0E` e descarta um
  VS15 perdido) e ao CARREGAR dados (`Nota.normalizarTodos` em `fromJson`
  corrige textos salvos antes do VS15).
- ⚠️ Além do VS15, o app embute um subset da **Noto Sans Symbols 2** (só os
  glifos ☐/☑/☒, `assets/fonts/NotoSansSymbols2-Regular.ttf`, ~2KB, OFL) e o
  usa como `fontFamilyFallback` no estilo do texto (campo e comentário):
  a fonte do app (Manrope/Roboto) NÃO tem esses glifos, então sem o subset
  alguns aparelhos caíam na fonte de emoji e o ☑ virava ✅ verde (VS15 não
  adianta se nenhuma fonte de texto do sistema tiver o glifo).
- O estilo do texto é montado em `build` (`_estiloCampo`: fonte do tema +
  fallback + fontSize/height) e REUSADO no hit-test (`_toqueTexto`) — assim
  as métricas do `TextPainter` batem com o texto renderizado.
- ⚠️ **Quadradinho maior REVERTIDO (V0.1.52 → V0.1.53):** a tentativa de
  ampliar os glifos ☐/☑ via `BuscaController.buildTextSpan` (fontSize×1.3,
  height compensado, faixa de toque 48px) quebrou a digitação nas linhas de
  to-do no aparelho do usuário (Enter duplicava texto, palavra gigante na
  2ª linha). REVERTIDO ao código original — o `buildTextSpan` voltou a só
  cuidar do destaque de busca e a faixa de toque voltou a 40px. NÃO re-aplicar.
- ⚠️ **V0.1.54 — tentado de novo e o USUÁRIO OPTOU POR MANTER como está:** a
  mesma família (aumentar o ☐/☑ no `buildTextSpan`, agora com
  `strutStyle`/`forceStrutHeight` p/ travar a linha) passa em teste headless MAS
  o teste NÃO exercita o IME/composição do GBoard — que é justamente o que
  quebrou na V0.1.52. Apresentado ao usuário; ele escolheu NÃO mexer no tamanho.
  Se um dia voltar ao assunto, a única rota segura discutida é: só aumentar o ☐
  quando a caixinha NÃO está focada (sem IME ativo) e voltar ao normal ao
  editar. NÃO reaplicar a versão "sempre maior".
- **Tocar no quadradinho** (faixa esquerda de ~40px de uma linha ☐/☑) alterna
  marcado/desmarcado — hit-test com `TextPainter` no `_toqueTexto`, detectado
  por `Listener` (eventos crus, sem disputa de gestos com o campo de texto).

### Voltar de outro app com o cursor
- **Reabertura do teclado (V0.1.38; refinada V0.1.54):** se a caixinha estava
  sendo editada ao SAIR do app (`_tinhaFocoAoParar`, gravado em
  `inactive`/`paused`/`hidden`), ao voltar (`resumed`) recriamos a conexão de
  entrada: `_foco.unfocus()` + `requestFocus()` + `SystemChannels.textInput
  'TextInput.show'`. ⚠️ O ATRASO é essencial (`_reabrirTeclado` em 220ms e
  520ms): logo no resume a janela ainda não recuperou o foco do sistema e o
  pedido de teclado seria ignorado — por isso a tentativa anterior (só
  `postFrame`, V0.1.37) falhava. O texto e o cursor ficam intactos (o
  controlador preserva a seleção).
- ⚠️ **V0.1.54 (anti-flicker "sobe e desce"):** o `unfocus()`+`requestFocus()`
  passou a ser feito ATOMICAMENTE dentro de `_reabrirTeclado` (antes o
  `unfocus()` era imediato no `resumed` e as duas reaberturas só chamavam
  `requestFocus`+`show` — o teclado subia/descia). A 2ª tentativa (520ms) só
  dispara se a 1ª NÃO reabriu (`somenteSeFechado`: pula se `viewInsets.bottom
  > 0`), evitando o duplo-show.
- O Android, ao sair do app, esconde o teclado e NÃO o reabre sozinho mesmo
  com o foco mantido — daí o bug intermitente "não consigo continuar
  digitando ao voltar", pior nas trocas rápidas.

### Esconder o teclado (setinha para baixo) — solta o foco (V0.1.42)
- **Bug corrigido:** ao apertar a setinha do teclado para escondê-lo, ele
  "saía e voltava" (às vezes precisava insistir 2-3×), pior clicando no FIM de
  um texto. Causa: o Android some com o teclado mas o Flutter MANTÉM o foco na
  caixinha — aí qualquer reconstrução (ou a correção de maiúscula em debounce,
  que faz `_ctrl.value = …` num campo focado) REABRE o teclado.
- **Solução:** `didChangeMetrics` detecta o teclado FECHANDO (viewInsets.bottom
  `>0 → 0`) e, se a caixinha tem foco e o app está `resumed`, solta o foco.
  O cursor some e o teclado fica fora até tocar na caixinha de novo —
  comportamento padrão. `_insetBottomAnterior` rastreia a altura; é semeado ao
  GANHAR foco (`_aoMudarFoco`) para funcionar mesmo na troca entre caixinhas
  com o teclado já aberto.
- ⚠️ **V0.1.54 (não desligar o teclado no meio da digitação):** o `unfocus()`
  virou DEBITADO — ao ver `bottom → 0`, agenda um `Timer` de 320ms
  (`_fecharTecladoTimer`) e só solta o foco se o teclado CONTINUAR fechado
  quando ele dispara; se `bottom` voltar a `>0` antes disso, cancela. Motivo:
  vários teclados (GBoard) reportam `bottom == 0` por um instante ao trocar de
  layout (emoji/símbolos/uma-mão/barra de sugestão) — o `unfocus()` imediato
  fechava o teclado sozinho durante a digitação (bug relatado). Testado em
  `melhorias_test.dart` ("altura 0 passageiro NÃO solta o foco").
- ⚠️ O guard `resumed` é essencial: ao SAIR para outro app o teclado também
  fecha, mas aí queremos PRESERVAR o foco para reabri-lo ao voltar (não brigar
  com `_reabrirTeclado`).
- ⚠️ **"Minimizar o teclado duas vezes" (V0.1.57):** a correção de maiúscula
  (`_debounce`, 2s) fazia `_ctrl.value = …` num campo AINDA focado → REABRIA o
  teclado se disparasse logo depois de o usuário esconder (intermitente, pior em
  listas numeradas onde a correção existe). Dois freios: (1) o callback da
  correção só age com o teclado À VISTA (`viewInsets.bottom > 0` e
  `_foco.hasFocus`); (2) `didChangeMetrics`, ao ver o teclado fechar, cancela o
  `_debounce` na hora (não só quando o unfocus dispara).

### Caderno (caixinha longa)
- `maxLines: 24`; além disso o texto rola por dentro (Scrollbar). Botão
  `unfold_more` alterna o scroll interno entre topo e pé.
- **Cursor sempre acima do teclado E do "+" (V0.1.38):** o `TextField` usa
  `scrollPadding: fromLTRB(20, 20, 20, 108)`. Ao mover o cursor (a cada
  tecla), o Flutter rola a PÁGINA (a `ReorderableListView`, que o Scaffold já
  encolhe para cima do teclado com `resizeToAvoidBottomInset`) para deixar o
  cursor a ≥108px da borda inferior — folga do FAB (56 + 16). É o mecanismo
  NATIVO do Flutter para manter o cursor visível ao digitar.
- ⚠️ **Toda a antiga maquinaria de trava de altura por timers/medições foi
  REMOVIDA na V0.1.38** (`_alturaMaxima`, `_topoConhecido`, `_maxAlturaCaixa`,
  `_ajustarVisibilidade`, `_ajustarAltura`, `_agendarAltura`, `_agendarAjuste`,
  `_agendarAjusteInsets`, `_aoFocar`, `_timerVis`, `_timerInsets`,
  `_posExterna`, `_recemRetomado`, o `didChangeDependencies` e a `ConstrainedBox`).
  Motivo: enquanto a caixinha rola por DENTRO, o Flutter acha o cursor visível
  dentro dela e não rola a página — então o cursor sumia atrás do "+". As duas
  tentativas de encolher a caixinha por timer (V0.1.36/V0.1.37) eram frágeis e
  falhavam "muitas vezes"; essa maquinaria também era a origem histórica do
  "tremor" e do "cursor no meio". A rolagem da PÁGINA + `scrollPadding` resolve
  tudo isso sem timers nem medições.
- Sem `ConstrainedBox`, a altura da caixinha é limitada só por `maxLines: 24`.

### Desfazer (undo)
- **Botão `undo` na barra da caixinha:** desfaz o "movimento" anterior, em
  VÁRIOS níveis. Usa `HistoricoTexto` (editor.dart): guarda o texto ANTES de
  cada movimento. Um novo movimento (novo ponto de desfazer) começa quando:
  (1) é a 1ª mudança desde que a caixinha abriu, (2) houve uma PAUSA na edição
  (`pausaMs`, 600ms), ou (3) o SENTIDO mudou (digitar ↔ apagar). Assim tanto
  DIGITAR quanto APAGAR são desfazíveis, e o desfazer volta bloco a bloco (não
  tecla por tecla). ⚠️ Corrige o bug histórico em que digitar NÃO criava ponto
  de desfazer e o undo só voltava o último apagamento.
- A correção automática de maiúscula (feita direto no controlador, fora de
  `_mudou`) chama `_historico.sincronizar()` — alinha o estado atual SEM criar
  um passo de undo espúrio.
- Ações da barra (centralizar, numerar, item de to-do) empilham o estado
  ANTES de agir via `empilhar()` + `suprimir()` (o registro automático das
  mudanças intermediárias é suspenso durante a ação) — desfazer volta ao
  estado anterior, inclusive desfazendo a centralização.
- Excluir caixinha, excluir projeto e mover entre abas mostram aviso com **Desfazer** por 4s.
- `mostrarAviso`/`mostrarAvisoAcao` (editor.dart) usam SnackBar **+ Timer** para forçar o fechamento mesmo com animações do sistema desativadas.

### Backup em arquivo (exportar/importar)
- **Exportar:** gera `adm-projetos-backup-AAAA-MM-DD-hhmm.json` (mesmo JSON do Storage) e abre o menu de compartilhamento (`share_plus`).
- **Importar:** escolhe arquivo (`file_picker`), valida o JSON e pergunta: **Substituir tudo** ou **Somar ao que existe** (mescla por id).
- **Restaurar de texto colado (V0.1.58):** ⚙️ → Backup → "Restaurar de um texto
  colado" (`RestaurarTextoScreen`) → cola o texto do botão **"Copiar backup"**
  (ou um JSON) → `projetosDeBackupColado` (storage.dart) reconstrói e importa
  (Somar/Substituir). Ordem de tentativa: (0) bloco `###TASKIX-BACKUP-JSON###`
  no fim = restauração FIEL; (1) JSON puro; (2) texto legível — neste caso as
  **caixinhas são separadas por linha(s) em branco** (V0.1.60; checkbox/
  comentário/link só vêm no bloco JSON). Recuperação de emergência quando não há
  arquivo nem nuvem. Nasceu do incidente 2026-08-22 (perda de dados na
  reinstalação).

### Backup automático (.bak) + snapshots + backup do Google (V0.1.42–45)
- **`.bak` no disco:** cada gravação (`salvar`/`marcarModificacaoEm`) guarda a
  versão ANTERIOR do `adm_projetos.json` em `adm_projetos.bak.json` (só quando
  o conteúdo muda). O `carregar()` RESTAURA do `.bak` se o principal estiver
  ausente, vazio ou corrompido (auto-cura — protege contra "apagou tudo" por
  escrita ruim; o .bak é o estado anterior bom). Se o principal existe e é um
  JSON válido vazio (usuário apagou de propósito), o `.bak` NÃO sobrepõe.
- **Snapshot por versão (V0.1.45):** ao ATUALIZAR o app (versão salva em
  SharedPreferences `ultima_versao_v1` ≠ `appVersao`), o arquivo como estava
  ANTES é copiado para `adm_projetos.json.v<versao>` ANTES de qualquer
  leitura/escrita (mantém as 5 mais recentes). Nenhuma versão nova sobrescreve
  os dados sem deixar a cópia anterior. A cadeia de restauração do
  `carregar()` é: principal → `.bak` → snapshots (mais novo primeiro).
- **Guarda anti-esvaziamento (V0.1.45):** `_gravar` BLOQUEIA gravações cuja
  lista fique VAZIA se o arquivo atual tem projetos — só a exclusão explícita
  do último projeto passa (`liberarEsvaziamento()` chamado em `_excluir`).
  Impede que um bug/versão nova "abra vazio e grave por cima".
- **Google Drive:** `AndroidManifest.xml` com `allowBackup="true"` +
  `fullBackupContent="true"` + `dataExtractionRules` (xml que inclui tudo:
  arquivos, sharedprefs, banco) — o Android passa a subir os dados do app
  para a conta Google do usuário e RESTAURA automaticamente ao reinstalar.
  ⚠️ Antes da V0.1.42 o atributo não existia e, com targetSdk 36, o backup do
  Google ficava DESLIGADO por padrão (perda irreversível ao desinstalar).

### Sincronização com a nuvem (Firebase) — 100% MANUAL (por botão)
- **`SyncService`** (sync_service.dart, ChangeNotifier): doc `usuarios/{uid}` no
  Firestore com `{dados: JSON, atualizadoEm: ms, email}`.
- ⚠️ **NADA sobe ou desce sozinho.** O app é SEMPRE local; a nuvem é só um
  backup opcional acionado por botão. Só existem duas operações, ambas manuais
  e disparadas nas Configurações (com nenhuma caixinha aberta):
  - **`enviarAgora()`** (botão "Enviar para a nuvem"): sobe o local. Seguro —
    apenas LÊ os projetos e envia; não toca na lista em memória.
  - **`baixarDaNuvem()`** (botão "Baixar da nuvem", com confirmação):
    `Storage.substituir()` pelos dados da nuvem.
- **Entrar com Google** só autentica e mostra o estado (`nuvemMaisNova` é apenas
  uma DICA, comparando `atualizadoEm` remoto vs local — nunca aplica sozinho).
- ⚠️ **Login NATIVO do Google (V0.1.61):** `entrarComGoogle` usa
  `google_sign_in` (`signIn` → `signInWithCredential`), NÃO mais
  `signInWithProvider(GoogleAuthProvider())`. O fluxo web "Generic IDP" dava
  `[firebase_auth/unknown] Failed to generate/retrieve public encryption key`
  mesmo com SHA-1 **e** SHA-256 registrados. O nativo usa o SHA-1 já registrado
  + `serverClientId` = web client (oauth_client type 3). `sair()` também faz
  `GoogleSignIn().signOut()`. Requer o provedor **Google habilitado** em
  Firebase Auth (senão dá `operation-not-allowed`, agora visível no dialog).
- 🐛 **Por que virou manual (regressão da perda de texto — V0.1.24):** o modo
  automático anterior aplicava a nuvem (inclusive o ECO do próprio envio) via
  `Storage.substituir()`, que TROCA os objetos do modelo por novos. Se isso
  acontecia enquanto o usuário digitava, a `_CaixaNota` aberta seguia gravando
  no objeto ANTIGO (descartado) → texto sumia e caixinha excluída "voltava".
  Salvar a cada tecla/foco/pausa NÃO resolvia (o defeito era a nuvem trocar os
  objetos por baixo dos dedos). Removidos: listener em tempo real
  (`snapshots()`), upload com debounce 3s e auto-apply no login.
- **`Storage`** é `ChangeNotifier` e guarda `atualizadoEm` no próprio arquivo;
  `marcarModificacaoEm(ms)` alinha o relógio após um envio.
- `ProjetosScreen` escuta o Storage e re-aponta a lista (sem cópia) após um
  "Baixar da nuvem".
- **Modo local (sem Firebase):** `main()` chama `Firebase.initializeApp()` em
  try/catch — se falhar (google-services.json ausente), o app segue 100%
  local e o botão "Entrar com Google" mostra aviso amigável.
- ⚠️ Ao CONFIGURAR o Firebase (google-services.json no `android/app/`), ainda
  é preciso aplicar o plugin `com.google.gms.google-services` no Gradle
  (settings.gradle.kts + app/build.gradle.kts), como no calistenia_app.
- **Micro-copy (V0.1.54):** as dicas da seção Nuvem explicam o fluxo —
  desconectado: "entre com o Google primeiro"; conectado: "toque em Enviar
  antes de atualizar/desinstalar; ao reinstalar entre com a MESMA conta e
  toque em Baixar".

### Lembretes rápidos (notificação local) — sininho (V0.1.54/55)
- **`LembretesService`** (lembretes.dart, ChangeNotifier singleton) sobre
  `flutter_local_notifications` + `timezone`. Inicializado no `main()`
  (try/catch, como o Firebase). Canal `lembretes` (Importance.high).
- Fluxo: 🔔 na tela inicial (à ESQUERDA da lupa) → `_LembreteSheet` (folha
  `isScrollControlled` + **`useSafeArea` V0.1.55** para não subir por baixo da
  barra de status): campo de texto + `ActionChip`s de tempo
  (30 min · 2 h · 4 h · 24 h · "Outro…") → `agendar(texto, Duration)`.
- ⚠️ **Fluidez da folha (V0.1.56):** SEM `autofocus` e com `Padding` SIMPLES
  (não `AnimatedPadding`). A V0.1.55 tinha foco atrasado ~280ms + `AnimatedPadding`
  e o usuário sentiu "dois estágios + travadinha": o foco atrasado abria o
  teclado num 2º movimento e o `AnimatedPadding` animava POR CIMA da animação do
  próprio teclado (lag). Agora a folha sobe limpa (sem teclado) e o teclado só
  abre quando o usuário toca no campo, seguido 1:1 pelo `Padding`. `initState`
  chama `recarregar()` para a lista já vir fresca do disco.
- **`agendar`** pede a permissão (Android 13+, `requestNotificationsPermission`)
  e chama `zonedSchedule` com `AndroidScheduleMode.exactAllowWhileIdle` — alarme
  EXATO. O instante é `agora + duração` computado em UTC (lembrete relativo, o
  fuso não altera o instante absoluto). O `payload` carrega o texto.
- **Botões de reprogramar na notificação (snooze, V0.1.55):** o aviso traz
  `AndroidNotificationAction` **30 min · 2 h · 24 h** (`_snoozes`; Android mostra
  até ~3). Tocar num botão chama `LembretesService.reagendarPorAcao` — ESTÁTICO
  e autossuficiente (roda no isolate de BACKGROUND, com o app fechado):
  `DartPluginRegistrant.ensureInitialized()` + init tz/plugin, mapeia o
  `actionId` → `Duration`, lê o `payload` (texto) e reagenda; edita a lista
  persistida (`_mexerPendentesPrefs`: tira o id que disparou, põe o novo). O
  handler top-level `respostaNotificacaoBackground` (`@pragma('vm:entry-point')`)
  é registrado em `initialize` (+ `_respostaNotificacaoForeground` p/ o app vivo,
  que ainda dá `recarregar()` na lista visível). `showsUserInterface:false` +
  `cancelNotification:true` nos botões.
- ⚠️ **`SharedPreferences.reload()` (V0.1.56):** o snooze grava a lista de
  pendentes noutro isolate (app fechado). Sem `reload()`, o cache em memória do
  isolate do app ficava velho e o lembrete reprogramado NÃO aparecia nos
  "agendados". `_carregarPendentes` e a leitura do contador de id (`agendar` e
  `reagendarPorAcao`) fazem `reload()` antes de ler; a folha chama `recarregar()`
  no `initState`.
- ⚠️ **Reforço de entrega (V0.1.57):** contra "às vezes sem som / não aparece na
  tela bloqueada / conteúdo não aparece / ~1 min atrasado":
  - **Canal NOVO `lembretes_v2`** (`_canal`, `Importance.max` + `playSound` +
    `enableVibration`). O Android CONGELA som/importância na criação do canal —
    por isso trocamos o id; o antigo `lembretes` é apagado (`deleteNotificationChannel`).
  - `_detalhes(texto)`: `Importance.max`, `category.reminder`,
    `visibility.public` (mostra na tela bloqueada), `playSound`,
    `enableVibration` e **`BigTextStyleInformation(texto)`** (mostra o texto
    escrito inteiro; sem BigText o corpo era truncado).
  - **Arredonda o disparo para o minuto** (`_quandoAgendar`: zera os segundos) —
    tocava nos segundos seguintes e parecia ~1 min atrasado. Como a duração é
    sempre ≥ 1 min, o alvo nunca cai no passado.
  - Manifesto ganhou **`SCHEDULE_EXACT_ALARM`** (cobre Android 12, onde
    `USE_EXACT_ALARM` não existe) — sem alarme EXATO o Doze atrasa/segura o
    disparo com a tela bloqueada.
  - ⚠️ Reincidência de "não chega com o app fechado" costuma ser OEM (Xiaomi/
    Samsung/etc. matam o app) → orientar o usuário a liberar o app da economia
    de bateria. Não há fix 100% em código para isso.
- **Pendentes:** guardados em SharedPreferences (`lembretes_pendentes_v1`, id em
  `lembretes_prox_id_v1`) só p/ EXIBIR (texto + horário) e cancelar; os vencidos
  são podados no load. `cancelar(id)` → `plugin.cancel(id)`. A fonte de verdade
  do agendamento é o AlarmManager do Android (dispara com o app fechado).
- **Android:** `AndroidManifest.xml` ganhou `POST_NOTIFICATIONS`,
  `USE_EXACT_ALARM` (concedida automaticamente a apps de lembrete — sem prompt),
  `RECEIVE_BOOT_COMPLETED`, `VIBRATE` + os 3 receivers do plugin
  (`ActionBroadcastReceiver`, `ScheduledNotificationReceiver`,
  `ScheduledNotificationBootReceiver`). `app/build.gradle.kts` habilitou
  **core library desugaring** (`isCoreLibraryDesugaringEnabled = true` +
  `desugar_jdk_libs:2.1.4`), exigido pelo plugin.

### Digitação por voz
- O formatador `LinhasNumeradas` só age quando o texto CRESCE e termina com `\n` — não interfere com backspace nem com voz.
- A correção de maiúscula (`maiusculaAposItem`) roda **2 segundos após pausa** na digitação (debounce), não durante — para não quebrar o ditado.

### Links (até 3) e títulos de vídeo
- A caixinha guarda até 3 links (`Nota.links`, cada um com `url` + `titulo`).
- **Botões do diálogo (V0.1.48/49/50):** "Colar" (cola a área de transferência no
  1º campo vazio, ou no 1º) e "Limpar" (apaga todos os campos) — além de
  "Fechar" e "Salvar". Layout: linha 1 = Colar · Limpar · Fechar; linha 2
  (alinhada à direita, sob "Fechar") = Salvar (um `Column` no `actions` do
  AlertDialog — o Salvar em `Row` único estourava a largura do diálogo).
  Colar dispara a busca de título.
- No diálogo de link, ao colar URL do YouTube, após 600ms de pausa busca o
  título via oEmbed (`youtube.com/oembed`) e mostra o preview — o título é
  SALVO junto com o link (não vai mais para o comentário).
- Os títulos (ou a URL, se não for vídeo) aparecem SEMPRE abaixo da caixinha,
  uma linha por link, mesmo sem abrir o comentário — e permanecem ao fechar e
  reabrir o projeto.
- `_buscarTitulosPendentes` (no initState e após salvar links) busca o título
  de links de YouTube que ainda não têm título (ex.: dados migrados) e salva.
- Migração de dados antigos: campo `link` → `links[0]`; o `comentario` antigo
  que era o eco do título vira `links[0].titulo` e é limpo (comentário manual
  sem link é mantido).

### Busca com destaque (V0.1.42 — reescrita)
- O termo ativo da busca é passado às caixinhas (`termoBusca`) e o destaque
  (fundo amarelo) é montado DENTRO do próprio `buildTextSpan` do TextField, por
  um `BuscaController extends TextEditingController` (editor.dart): o campo usa
  `_ctrl` do tipo `BuscaController` e `build` faz `_ctrl.termo = termoBusca`.
- ⚠️ **Por que mudou:** o antigo `_GrifoBuscaPainter` (CustomPaint por cima do
  texto) recalculava a geometria do TextField à mão e às vezes marcava a
  palavra/linha ERRADA (bug relatado). Como agora o destaque faz parte do MESMO
  layout do texto, nunca sai do lugar. Quando `termo` está vazio, o controlador
  delega ao `super.buildTextSpan` (preserva o sublinhado de composição do IME).

### Busca GLOBAL na tela inicial (lupa) — V0.1.42
- A lupa da tela inicial (`ProjetosScreen`) agora busca **tudo**: nomes de
  projetos E o conteúdo (texto + comentário) das caixinhas em Tarefas e Ideias
  de todos os projetos. Com termo, `_resultadosBusca` monta um `ListView` com
  duas seções: "PROJETOS" (por nome) e "NAS CAIXINHAS" (`_ResultadoBusca`:
  projeto + aba + trecho destacado).
- Tocar num resultado de caixinha chama `_abrirNota`, que abre a
  `ProjetoScreen` já na aba certa (`abaInicial`), com a busca ativa e o termo
  destacado (`termoInicial`) e rolando até a caixinha (`notaAlvo` →
  `_irParaNota` via `Scrollable.ensureVisible` na GlobalKey da caixinha).

### Menu de seleção (recortar/copiar/colar) ACIMA
- O menu de seleção usa o posicionamento PADRÃO do Flutter
  (`contextMenuBuilder: _menuSelecao` → `AdaptiveTextSelectionToolbar.editableText`),
  que abre ACIMA da seleção quando cabe.
- **Por que mudou (V0.1.38):** antes era forçado ABAIXO (`_menuSelecaoAbaixo`,
  `anchorAbove` impossível) para não cobrir a barra da caixinha. Mas abaixo da
  seleção o menu ficava em cima das ALÇAS de arrastar (que ficam abaixo do
  texto) — não dava para estender a seleção para várias palavras. Acima da
  seleção as alças ficam livres. Compensação: para seleções na 1ª linha o menu
  pode ficar perto da barra da caixinha (aceitável perto de não conseguir
  selecionar).
- Os labels (Copiar/Colar/…) e a posição já vêm resolvidos pelo
  `AdaptiveTextSelectionToolbar.editableText` — não precisa mais montar os
  botões na mão.

### Comentário e títulos dos links
- Em **Tarefas:** o campo de comentário manual é toggle (expande/recolhe).
- Em **Ideias:** sempre visível se existir.
- Os TÍTULOS dos links ficam na mesma sub-caixinha, ACIMA do campo de
  comentário, e são sempre visíveis quando há links (nos dois modos).
- Texto em cor mais fraca (alpha 0.55).

### Backup
- Botão ao lado da engrenagem na tela principal ("Copiar backup"): copia
  **todos os projetos** para o clipboard. **V0.1.59:** além da parte legível
  (`- - -`), anexa no fim um bloco `###TASKIX-BACKUP-JSON###` + o JSON COMPLETO
  (`exportarJson`). Assim "Restaurar de um texto colado" reconstrói TUDO
  fielmente (caixinhas separadas, comentários, links, checkbox). Backups antigos
  (só a parte legível) ainda restauram, mas com uma caixinha por aba.

### Salvamento automático
- `Storage.instance.salvar()` é chamado após cada ação (criar, editar, excluir, reordenar, check, link, comentário).
- Dentro do `_CaixaNota`, o texto **salva a CADA TECLA** (`_mudou` grava na hora) —
  o debounce de 2s ficou SÓ para a correção de maiúsculas (`maiusculaAposItem`),
  nunca para o salvamento (ditado por voz não pode ser interrompido).
- **Arquivo v2:** `{"atualizadoEm": ms, "projetos": [...]}` — dados e horário
  gravados JUNTOS e de forma SÍNCRONA (após o 1º carregamento): ao retornar de
  `salvar()`, já está no disco. O horário nunca fica "mais novo" que o conteúdo
  (senão a nuvem velha sobrescreveria o texto novo no próximo login).
- Ao PERDER o foco e ao fechar a tela/o widget, o texto dos controladores é
  DERRAMADO no modelo (`_guardarTudo`) antes de `Storage.instance.salvar()` —
  cobre o texto que a IME ainda estava compondo (última palavra do GBoard) na
  hora de sair rápido da tela. O campo de comentário usa controlador próprio
  (`_ctrlComentario`, criado no initState) e só é derramado quando visível,
  para não sobrescrever comentário salvo por outro caminho.
- Ao fechar a tela ou o widget, força `Storage.instance.salvar()`.
- `_SalvadorDeVida` (main.dart) salva quando o app sai de primeiro plano (pausa/inativo/oculto) — reforço contra perder digitação recente ao fechar o app.
- ⚠️ **NUNCA copiar a lista do Storage para o estado das telas** (`List.of`):
  as telas devem apontar para a MESMA lista interna (`Storage._projetos`) —
  copiar desliga as edições do salvamento e os dados "somem". `_aoMudarStorage`
  e `_abrirConfig` re-atribuem a referência, sem cópia.

---

## 7. CI/CD — Build do APK

**Trigger:** push na `main` (pastas `lib/`, `pubspec.yaml`, `android/`, `.github/workflows/`) + manual (`workflow_dispatch`).

**Fluxo:**
1. Checkout + Java 17 + Flutter 3.44.7
2. `flutter pub get`
3. Decodifica `secrets.KEYSTORE_BASE64` → `android/app/upload-keystore.jks`
4. Cria `android/key.properties` com senhas do `secrets.KEYSTORE_PASSWORD`
5. `flutter build apk --release`
6. Publica APK na release `v0.1.0` (sobrescreve a cada build com `--clobber`)

**Secrets necessários:** `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`

**Keystore local:** `android/app/upload-keystore.jks` + `android/key.properties` (não commitados — `.gitignore` ignora `*.jks` e `key.properties`).

---

## 8. Comandos Úteis (sempre na pasta `/root/adm-projetos`)

```bash
# Análise estática
flutter analyze

# Testes (65 testes)
flutter test

# Build local (não usado — build é feito no GitHub Actions)
flutter build apk --release

# Commit + push (usar este padrão)
cd /root/adm-projetos && git add -A && \
  git -c user.name="Vinicius Tristao" -c user.email="viniciostristao@gmail.com" \
  commit -m "<mensagem>" && git push

# Acompanhar build
gh run list --repo viniciostristao1/adm-projetos --limit 1 --json status,conclusion

# ⚠️ REGRA OBRIGATÓRIA: SEMPRE avisar o usuário quando o build do APK
# terminar (sucesso ou falha). Após um push, aguardar ~13 min (ou usar
# `gh run watch <id> --exit-status`) e informar o resultado — ex.: "APK
# publicado: V0.1.32". Se o build ficar parado (in_progress sem logs por
# muito tempo), cancelar e re-disparar com `gh workflow run`.

# Baixar APK da release
gh release download v0.1.0 --repo viniciostristao1/adm-projetos --clobber
```

---

## 9. Padrões de Código

### Adicionar nova cor ao tema
1. Adicionar campo `final Color` em `AppCores` (`cores.dart`)
2. Atualizar construtor, `copyWith`, `lerp`
3. Definir valor nas 5 constantes (`azul`, `escuro`, `neumB`, `bege`, `claude`)
4. Acessar via `Theme.of(context).extension<AppCores>() ?? AppCores.azul`

### Adicionar novo botão na barra da caixinha
- Usar `_BotaoMini(icone:, tooltip:, onTap:, cor: onBarra)` dentro do `Row` da barra de ferramentas em `_CaixaNotaState.build`.

### Adicionar nova tela
- Criar arquivo `lib/nova_tela.dart` com `StatefulWidget`
- Navegar via `Navigator.push(context, MaterialPageRoute(builder: (_) => NovaTela(...)))`
- Após retorno, chamar `_salvar()` + `setState()` se necessário.

### Dependências
- **path_provider:** `^2.1.6` — acesso ao diretório de documentos
- **shared_preferences:** `^2.5.5` — preferências do usuário
- **pdf:** `^3.11.3` + **printing:** `^5.14.2` — gerar/compartilhar PDF do projeto
- **share_plus:** `^12.0.1` — compartilhar arquivo de backup
- **file_picker:** `^10.3.3` — escolher arquivo de backup para importar
- **image_picker:** `^1.1.2` — escolher imagem da galeria (OCR)
- **google_mlkit_text_recognition:** `^0.14.0` — OCR local (ML Kit)
- **firebase_core / firebase_auth / cloud_firestore** — nuvem manual (§6)
- **flutter_local_notifications:** `^19.0.0` + **timezone:** `^0.10.0` —
  lembretes com notificação local (item 5, V0.1.54). Exigem core library
  desugaring no `app/build.gradle.kts` (`desugar_jdk_libs:2.1.4`).
- **flutter_launcher_icons:** `^0.14.4` — gerar ícones do app (dev only)
- Não há pacote `http` — requisições HTTP usam `dart:io` `HttpClient` diretamente.

---

## 10. Testes (66 testes)

### `test/widget_test.dart` (8 testes)
- Serialização de `Nota`
- Serialização de `Projeto` com tarefas
- Projeto com listas vazias
- Migração de dados antigos (`notas` → `tarefas`)
- Serialização de `NotaLink` (até 3 links com título)
- Migração de `link` antigo → `links[0]` (título vindo do comentário-eco)
- Comentário manual sem link é mantido; `centralizada` serializa

### `test/numeracao_test.dart` (11 testes)
- `proximoNumeroLista`: vazio, sequência existente, sem números
- `LinhasNumeradas`: Enter cria número, sem alteração sem newline, backspace não re-insere, Enter sem número não numera, sequência 1→2→3
- `maiusculaAposItem`: maiúscula após prefixo, já maiúsculo, sem prefixo

### `test/salvamento_test.dart` (3 testes)
- Texto digitado sobrevive à saída imediata da tela (sem esperar timers)
- Texto em composição do IME sobrevive à saída imediata
- Dispose derrama o texto do controlador para o modelo (`_guardarTudo`)

### `test/todo_test.dart` (5 testes)
- `LinhasNumeradas`: Enter continua `☐` depois de linha `☐` e de linha já marcada `☑` (regressão V0.1.24: só `☐` criava), e dado antigo sem VS15 ganha `☐\uFE0E `
- `Nota.fromJson` normaliza quadradinhos antigos sem VS15 (regressão: carregava como emoji)
- Toque no quadradinho de dado antigo (sem VS15) grava `☑\uFE0E` (não vira emoji)

### `test/undo_link_test.dart` (7 testes)
- Desfazer restaura a palavra digitada e apagada (composição realista do IME)
- Desfazer restaura a rajada inteira de apagamentos
- Diálogo de links abre sem exceção (regressão da tela branca)
- Digitar URL e Salvar no diálogo não crasham
- Centralizar com seleção centraliza a LINHA (espaços calculados) e desfazer reverte
- Centralizar sem seleção mostra aviso e não altera nada
- Busca destaca o termo no texto da caixinha (via `BuscaController`; a caixinha
  some da lista quando o termo não ocorre)

### `test/melhorias_test.dart` (4 testes — V0.1.42 / V0.1.54)
- to-do criado numa 2ª linha VAZIA nasce na 2ª linha (regressão do bug #2 —
  `_linhaDoCursor` sem o recuo)
- lupa global acha palavra dentro de Ideias e, ao tocar, abre a `ProjetoScreen`
  na aba certa mostrando a caixinha
- lupa global também acha projeto por nome (seção "PROJETOS")
- **(V0.1.54)** esconder o teclado solta o foco só APÓS o debounce; e um
  "altura 0" passageiro (troca de layout do teclado) NÃO solta o foco

### `test/desfazer_test.dart` (7 testes)
- `HistoricoTexto` (undo multi-nível): digitar uma rajada cria UM ponto de
  desfazer; rajada de apagamento empilha uma vez; apagar/digitar/apagar cria
  movimentos separados (troca de sentido); PAUSA entre digitações cria níveis
  separados; `empilhar`/`suprimir` para ações da barra; limpar tudo é
  desfazível; `comecar` zera o histórico

### `test/fonte_test.dart` (1 teste)
- O subset embutido (Noto Sans Symbols 2) carrega e renderiza ☐/☑/☒ com glifo real (métrica diferente da fonte de teste — garante que o fallback consulta a fonte e não cai no tofu/emoji)

### `test/tema_test.dart` (7 testes)
- `Modo` tem exatamente os 5 temas (Azul, Escuro, Dark Game, Bege, Claude Code)
- Nomes antigos (claro/bege/begeNeum) não existem mais
- Os 5 temas constroem as superfícies (Caixa3D, BotaoNeum, Fundo, TextField) sem erro

### `test/backup_test.dart` (11 testes — V0.1.43/44/45)
- `salvar` guarda a versão anterior no `.bak`
- `carregar` restaura do `.bak` quando o principal está corrompido
- `carregar` restaura do `.bak` quando o principal sumiu
- Esvaziamento explícito (último projeto excluído → `liberarEsvaziamento`) persiste
- Gravação VAZIA é bloqueada quando o arquivo tem conteúdo (guarda anti-esvaziamento)
- Mudança de versão preserva snapshot do arquivo anterior (`adm_projetos.json.v<versao>`)
- `carregar` restaura de snapshot de versão anterior
- JSON truncado no meio é REPARADO (recupera os projetos gravados antes do corte)
- Um projeto inválido não derruba os demais (carregamento tolerante)
- Principal ilegível é preservado em `.corrompido` (1ª cópia, nunca sobrescrita)

---

## 11. Restrições e Cuidados

- **⚠️ NUNCA apagar/sobrescrever o conteúdo do usuário** — ver a "REGRA DE
  OURO" no topo deste arquivo: snapshot por versão, `.bak`, guarda
  anti-esvaziamento e testes de `backup_test.dart` são OBRIGATÓRIOS em toda
  nova versão.
- **NÃO usar `http` package** — usar `dart:io` `HttpClient` para requisições (app Android-only, não precisa de compatibilidade web).
- **Não remover `_debounce` de 2s** — necessário para ditado por voz.
- **Não usar `const` com acesso a campo de instância** (ex: `const FloatingActionButtonThemeData(backgroundColor: AppCores.azul.fab)` — dá erro de compilação).
- **Sempre rodar `flutter analyze` antes de commitar** — sem issues.
- **Sempre rodar `flutter test`** — 65 testes devem passar.
- **Nunca commitar `android/key.properties` ou `*.jks`** — já no `.gitignore`.
- **Assinatura do APK é fixa** — permite atualizar o app sem desinstalar.

---

## 12. Fluxo de Release (versão do app)

A cada publicação de APK:

1. **Incrementar** `appVersao` em `lib/versao.dart` (ex.: `V0.1.22` → `V0.1.23`)
   e o `version:` no `pubspec.yaml` (`0.1.22+22` → `0.1.23+23`).
2. A versão aparece no topo da tela principal (ao lado de "ADM-projetos") —
   o usuário confirma que está rodando o APK certo.
3. **Informar o número da versão na resposta do chat** (ex.: "Versão publicada: **V0.1.23**").

## 13. Histórico de Decisões

| Decisão | Motivo |
|---|---|
| JSON local em vez de Firebase | Simplicidade, offline-first, sem custo |
| 5 temas (Azul/Escuro/Dark Game/Bege/Claude Code) | Preferência do usuário; Bege é claro, os demais escuros |
| Tema Claude Code (terminal) com JetBrains Mono | Escolha do usuário: preto-quente + terracota + fonte mono, cartões como linhas de 1px |
| Prateleira "Recentes" (5 projetos) na página principal | Ideia do usuário (prateleira rolante) aplicada aos projetos mais recentes |
| Seções "EM ANDAMENTO"/"OUTROS" na lista de projetos | Ideia do usuário: o marcador de em andamento vira agrupamento; arrastar só dentro da seção |
| Densidade Confortável/Compacto nas Configurações | Ideia do usuário: mais conteúdo por tela, valendo para lista e caixinhas |
| Data do último envio à nuvem na linha "RECENTES" | Pedido do usuário: saber quando o backup na nuvem foi feito |
| Keystore fixa (não debug) | Evitar conflito de assinatura entre builds |
| Release `v0.1.0` sobrescrita | Evitar cota de artifacts do GitHub |
| `LinhasNumeradas` age só ao crescer texto | Impede que backspace recrie números |
| Maiúscula com debounce 2s | Não quebrar digitação por voz |
| Abas Tarefas/Ideias | Separar tarefas de ideias futuras |
| `dart:io` em vez de `http` | Não adicionar dependência extra |
| Sem `jumpTo` da lista durante a rolagem do usuário | Era o "tremor" ao rolar a página com uma caixinha focada |
| Derramar controladores no modelo ao perder foco/fechar | Texto em composição da IME não se perde ao sair rápido |
| Nuvem 100% manual (por botão), sem sync automático | Auto-apply da nuvem trocava os objetos do modelo durante a digitação → perda de texto / caixinha excluída voltando (V0.1.24) |
| Reabrir o teclado ao voltar de outro app (unfocus+refocus) | Android fecha a conexão de IME mas mantém o foco → teclado não reabria sozinho (V0.1.37) |
| Undo multi-nível por movimento (pausa / troca de sentido) | Digitar não criava ponto de desfazer e o undo só voltava 1 movimento (V0.1.37) |
| **Reabrir teclado com ATRASO (180/480ms) + flag `_tinhaFocoAoParar`** | O `postFrame` da V0.1.37 era cedo demais (janela ainda sem foco do sistema) → teclado seguia sem reabrir (V0.1.38) |
| **`scrollPadding` (rola a PÁGINA) no lugar da trava de altura por timers** | A rolagem INTERNA da caixinha fazia o Flutter achar o cursor visível → cursor atrás do "+"; toda a maquinaria de altura (V0.1.36/37) era frágil e era origem do "tremor"/"cursor no meio" (V0.1.38) |
| **Menu de seleção ACIMA (padrão) no lugar de forçado abaixo** | Abaixo cobria as alças de arrastar → não dava para selecionar várias palavras (V0.1.38) |
| **Nome visível → "Taskix" (V0.1.42)** | Pedido do usuário; só o nome exibido (título + launcher + MaterialApp.title), o pacote/código seguem `adm_projetos` |
| **Ordem dos botões da barra configurável (V0.1.42)** | Pedido do usuário; `BarraController` + `OrdemBarraScreen` (arrastar), uma ordem para todas as caixinhas |
| **Esconder teclado solta o foco (V0.1.42)** | O teclado "saía e voltava"; `didChangeMetrics` faz unfocus ao fechar (só `resumed`, para não brigar com a reabertura ao voltar de app) |
| **`_linhaDoCursor` sem recuo (V0.1.42)** | Criar to-do/numerar numa 2ª linha vazia caía na 1ª linha; agora fica na linha exata do cursor |
| **Destaque de busca via `BuscaController.buildTextSpan` (V0.1.42)** | O `CustomPaint` (`_GrifoBuscaPainter`) marcava a palavra/linha errada; no layout do texto o destaque nunca desalinha |
| **Lupa da tela inicial vira busca GLOBAL (V0.1.42)** | Pedido do usuário: achar qualquer palavra em Tarefas/Ideias de qualquer projeto e ir até a caixinha |
| **ConfigSheet com `showDragHandle` (V0.1.42)** | Não dava para fechar arrastando (o scroll do conteúdo engolia o gesto) |
| **Quadradinhos ☐/☑ maiores (V0.1.52)** | Pedido do usuário; `BuscaController.buildTextSpan` amplia o glifo (fontSize×1.3, height compensado p/ a linha não crescer) e a faixa de toque vai a 48px |
| **Quadradinho maior REVERTIDO (V0.1.53)** | A V0.1.52 quebrou a digitação nas linhas de to-do no aparelho do usuário (Enter duplicava, palavra gigante na 2ª linha); revertido ao original — a lição: NÃO desenhar o glifo ☐/☑ com estilo próprio no buildTextSpan, o TextField deixa de renderizar o texto corretamente com IME |
| **ConfigSheet: Tema nasce fechado (V0.1.52)** | Pedido do usuário; nenhuma seção abre sozinha — todas esperam o toque na flechinha |
| **Caixinha do tema Claude um pouco mais clara (V0.1.42)** | Pedido do usuário; interior `#161617→#1E1E20` e barra `#111213→#18181A`, cada tom em separado |
| **ConfigSheet `isScrollControlled` + 90% (V0.1.54)** | Pedido do usuário: a folha ficava baixa e a seção Nuvem, ao expandir, caía fora do visível; agora usa até 90% da tela e rola com folga |
| **Teclado: unfocus debitado 320ms (V0.1.54)** | Pedido do usuário ("teclado pisca/desliga sozinho digitando"); teclados reportam altura 0 passageira ao trocar de layout — o unfocus imediato fechava o teclado no meio da digitação. Debounce com re-checagem + reabertura sem duplo-show |
| **Lembretes com notificação — sininho (V0.1.54)** | Pedido do usuário: lembrete rápido em 3 toques; `flutter_local_notifications`, alarme EXATO via `USE_EXACT_ALARM` (sem prompt), lista de pendentes p/ cancelar |
| **Checkbox maior — MANTIDO como está (V0.1.54)** | Mesma família da V0.1.52 (buildTextSpan) re-quebraria o IME; teste headless não pega. Apresentado ao usuário, que optou por NÃO mexer no tamanho. Rota segura futura: só aumentar quando NÃO focado |
| **Botões de snooze na notificação (V0.1.55)** | Pedido do usuário: reprogramar (30 min·2 h·24 h) direto no aviso, sem escrever de novo; `AndroidNotificationAction` + handler de background `@pragma('vm:entry-point')` que reagenda com o app fechado. Android mostra até ~3 botões → escolhidos 3 |
| **Folha de lembrete: useSafeArea + subida suave (V0.1.55)** | Pedido do usuário: a folha subia por baixo da barra de status e "travava" ao subir. `useSafeArea:true` + `maxHeight 92%`; foco do campo com atraso (~280ms) + `AnimatedPadding` no lugar de `autofocus`+`Padding` |
| **Limpeza de artefatos + reescrita de histórico (V0.1.55)** | Pedido do usuário (autorizado): caches locais da VPS (~191 MB), runs antigos do GitHub Actions e `git filter-branch` p/ remover o `app-release.apk` de 51 MB do histórico (force-push). O `.gitignore` já barra o APK; a regra continua: NUNCA commitar `app-release.apk` |
| **Folha de lembrete: fluidez revista (V0.1.56)** | O foco atrasado + `AnimatedPadding` da V0.1.55 deram "dois estágios + travadinha". Revertido p/ SEM autofocus + `Padding` simples (segue o teclado 1:1); teclado só abre ao tocar no campo |
| **Snooze aparece nos agendados: `reload()` (V0.1.56)** | O snooze grava a lista noutro isolate; sem `SharedPreferences.reload()` o app mostrava cache velho e o lembrete reprogramado sumia da lista |
| **Notificação: som/tela bloqueada/conteúdo/atraso (V0.1.57)** | Canal novo `lembretes_v2` (max+som — o Android congela o canal antigo), `BigTextStyle` (mostra o texto), `visibility.public` (tela bloqueada), arredonda o disparo ao minuto (fim do "~1 min atrasado") e `SCHEDULE_EXACT_ALARM` (Android 12/Doze). Entrega com app morto pode depender do OEM (bateria) |
| **Teclado "minimizar 2×" (V0.1.57)** | A correção de maiúscula reabria o teclado num campo ainda focado ao esconder; agora só corrige com o teclado à vista + cancela o debounce ao fechar |
| **NUNCA mandar desinstalar p/ atualizar (incidente 2026-08-22)** | Sugeri desinstalar antes da V0.1.57 (p/ recriar o canal de notificação). A reinstalação restaurou um **auto-backup ANTIGO do Android** e o usuário perdeu o conteúdo recente. Update in-place preserva tudo; canal novo/permissões aplicam in-place. **Sempre instalar por cima.** |
| **Restaurar de texto colado (V0.1.58)** | Resposta ao incidente: recuperar projetos a partir do texto do "Copiar backup" (o único backup que o usuário tinha). `projetosDeBackupColado` + `RestaurarTextoScreen`. Lição maior: o app precisa de backup MENOS escondido (ver §14) |
| **"Copiar backup" lossless + erro real do login (V0.1.59)** | Pedido do usuário: copiar deve preservar caixinhas/comentários/links → bloco JSON completo anexado (`marcadorBackupJson`). E `_entrarGoogle` passou a mostrar o ERRO REAL (antes engolia como "Firebase não configurado"). **Diagnóstico:** o SHA-1 do keystore de release BATE com o registrado no `google-services.json` → a falha do login Google é server-side (provedor Google no Console / consent), não assinatura |
| **Restaurar separa caixinhas por linha em branco (V0.1.60)** | Pedido do usuário ("organizado por pasta e caixinha separadas"). O texto antigo do "Copiar backup" não delimita caixinhas → `caixinhas()` divide cada aba nos espaços em branco. |
| **Login Google NATIVO (V0.1.61)** | O `signInWithProvider` (fluxo web Generic IDP) dava "Failed to generate/retrieve public encryption key" mesmo com SHA-1 **e** SHA-256 registrados. Trocado para `google_sign_in` (`signInWithCredential`), que usa o SHA-1 nativo e não passa pelo fluxo web problemático |

---

## 14. Sugestões futuras (backlog de ideias)

> Ideias levantadas e ainda NÃO implementadas (nenhuma aprovada até agora).
> Ordem = da mais sinérgica com o que já existe para a menos.

- ⭐ **Data de vencimento por tarefa + lembrete automático** — marcar "vence tal
  dia/hora" numa caixinha e ela agenda a notificação sozinha (reusa
  `LembretesService`); tarefas atrasadas ganham destaque. Fecha o ciclo notas ↔
  lembretes.
- **Widget na tela inicial do Android** com as tarefas de um projeto —
  **INTERESSA ao usuário, mas NÃO agora** (marcado 2026-08-21 p/ retomar depois).
- **Arquivar projeto** (em vez de só excluir) — concluídos saem da lista
  principal sem perder conteúdo; aba/filtro "Arquivados".
- **Fixar (pin) projeto no topo** — além de "em andamento".
- **Lembrete recorrente** (diário/semanal) — reusa o motor de notificação
  (`matchDateTimeComponents`).
- **Etiquetas/cores por projeto** + filtro rápido.
- **"Limpar concluídas"** — apagar/arquivar de uma vez as caixinhas marcadas.
- **Compartilhar 1 projeto como texto** (hoje há PDF e "copiar tudo").
