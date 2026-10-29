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
5. **Bump de versão** — sempre incrementar o `version:` do `pubspec.yaml` e
   regenerar `lib/versao.dart` (`dart tool/gerar_versao.dart`) ao publicar
   (fluxo na seção 12; `test/versao_test.dart` garante).

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
├── main.dart            # Entry point + temas (Azul/Escuro/Dark Game/Bege/Terracota/Ônix) — abre no HomeShell
├── home_shell.dart      # HomeShell (V0.1.173): barra inferior FLUTUANTE Projetos·Muse·Estudos (IndexedStack); aba Estudos embute o ProjetoScreen
├── muse_blob.dart       # MuseBlob: rosto da Muse (IMAGEM em assets/muse/, V0.1.178) — personagem rosa; o ANEL neon muda por tema (asset escolhido via AppCores); FORA de lib/chat/ (barra usa sem puxar o chat)
├── models.dart          # Nota, Projeto — serialização JSON
├── storage.dart         # Persistência local (singleton Storage) + exportarJson/substituir + recentes (últimos abertos) + backup .bak
├── tema.dart            # TemaController (ChangeNotifier) + enums Modo, ModoFonte e Densidade + corFoco/corProximos (cores das seções FOCO/PRÓXIMOS)
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
├── seguranca.dart       # hashSenha/gerarSalt (SHA-256 salgado) — tranca de projeto (V0.1.93)
├── sync_service.dart    # SyncService (Firebase Firestore) — nuvem 100% MANUAL (por botão)
├── lembretes.dart       # LembretesService (flutter_local_notifications) — lembretes rápidos
│                        #   com notificação local do Android (item 5, V0.1.54)
├── versao.dart          # GERADO pelo CI a partir do `version:` do pubspec.yaml
│                        # (`dart tool/gerar_versao.dart`) — NÃO editar à mão (ver §12)
├── voz_config.dart      # VozController (velocidade 0.85–1.25 + voz dii/faber,
│                        # `voz_velocidade_v1`/`voz_id_v1`) — seção "Voz da Muse"
│                        # nas Configurações; "Fala devagar" por conversa (menu ⋮
│                        # da Muse, `Conversa.falaDevagar` soma +0.16)
```

---

## 3. Modelos de Dados

### Nota (`models.dart`)
| Campo | Tipo | JSON key |
|---|---|---|
| `id` | `String` | `id` |
| `texto` | `String` | `texto` |
| `concluida` | `bool` | `concluida` |
| `minimizada` | `bool` | `minimizada` (omisso se false; ausente = false — V0.1.86) |
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
| `cor` | `String?` | `cor` (nome em `mapaCoresPasta`; dirige as seções FOCO/PRÓXIMOS) |
| `senhaHash` | `String?` | `senhaHash` (V0.1.93 — SHA-256 salgado; omisso se null) |
| `senhaSalt` | `String?` | `senhaSalt` (V0.1.93 — salt do hash; omisso se null) |

> **Backward compat:** `fromJson` migra chave antiga `notas` → `tarefas`.
> `senhaHash`/`senhaSalt` ausentes = projeto sem senha (`temSenha` false).

---

## 4. Sistema de Temas

### Modo (enum em `tema.dart`)
`azul`, `escuro`, `neumB` (Dark Game), `bege`, `claude` (rótulo **Terracota**),
`onix` (**Ônix**), `luz` (rótulo **Claro**) — **7 temas** (estilo inspirado no app
Calis Timer: azul = navy plano com accent azul; bege = claro com as cores do tema
madeira — tons amadeirados com accent laranja-marrom). **Bege e Claro** são os
claros (rodam em `ThemeMode.light`); os demais são escuros. `claude` é o tema
terminal (rótulo **Terracota** desde V0.1.64; `name` do enum segue `claude`):
preto-quente #0C0C0D, borda 1px #2A2A2B, acento terracota #D97757, fonte
JetBrains Mono. `onix` é o tema estilo ChatGPT: preto liso #0D0D0D, texto branco
#ECECEC, verde discreto #19C37D só no accent, fonte sem serifa padrão. **`luz`
(Claro, V0.1.174)** é o visual dos mockups de redesenho: fundo cinza-claro FRIO
(#EEF1F6→#E6EBF2), cartões/caixinhas BRANCOS que flutuam com sombra suave, texto
quase-preto #121418, acento AZUL #2E6BFF, fonte sem serifa padrão. ⚠️ `name` do
enum é **`luz`** (não `claro`): `claro` é nome LEGADO migrado p/ `azul` na carga
(`TemaController.carregar`) — reaproveitá-lo faria o tema novo cair na migração.

- **Home "sem caixa" (Bege e Ônix):** na tela principal as pastas de projeto
  ficam LISAS (sem cartão nem borda — `semCaixa` no item da lista e nos
  recentes). No Bege, o fundo da home usa a cor da caixinha (#E0D1B9, "bege
  queimado") via `Scaffold.backgroundColor`; no Ônix o fundo já é o preto do
  tema. Os demais temas mantêm o cartão com borda.

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

> **V0.1.173 — HomeShell + barra flutuante:** o app abre no `HomeShell`
> (`lib/home_shell.dart`), com uma **barra inferior FLUTUANTE** de 3 destinos —
> **Projetos** (a `ProjetosScreen` abaixo) · **Muse** (centro → `ConversasScreen`,
> a LISTA de conversas) · **Estudos** (o projeto reservado "Estudos" embutido em
> modo pastas). Abrir um projeto ou uma conversa empilha uma rota CHEIA (a barra
> some); o voltar traz a barra. A antiga **prateleira** de acessos rápidos e a
> função **Recentes** foram REMOVIDAS.

```
ProjetosScreen (lista de projetos — aba 1 do HomeShell)
  ├─ FAB [+] → criar projeto
  ├─ 🔔 (à ESQUERDA da lupa) → folha "Lembrete rápido": escrever + tocar num
  │       tempo (30 min · 2 h · 4 h · 24 h · Outro…) agenda uma NOTIFICAÇÃO
  │       local do Android; lista os agendados com X p/ cancelar (item 5,
  │       V0.1.54). Detalhe em §6 "Lembretes".
  ├─ 🔍 → busca GLOBAL (projetos por nome + conteúdo das caixinhas em
  │       Tarefas/Ideias); tocar num resultado abre a caixinha
  │   (ACESSOS RÁPIDOS / prateleira RECENTES·ASSISTENTE·ESTUDOS REMOVIDOS na
  │    V0.1.173 — navegação migrou p/ a barra flutuante do HomeShell; Muse e
  │    Estudos viraram abas.)
  ├─ SEÇÕES (V0.1.46; FOCO/PRÓXIMOS por cor em V0.1.94): a lista vira seções
  │    quando há ≥1 projeto em FOCO, EM ANDAMENTO ou PRÓXIMOS. Ordem por
  │    PRIORIDADE: "FOCO · N" → "EM ANDAMENTO · N" → "PRÓXIMOS · N" →
  │    "OUTROS · N". Arrastar só move DENTRO da seção (_reordenarComSecoes). A
  │    montagem das seções e a classificação são ÚNICAS e compartilhadas entre
  │    exibição e reorder: `_linhasComSecoes(projetos)` (sequência
  │    cabeçalho+Projetos, ou null = lista plana), `_secaoDoProjeto(p)` (índice
  │    0=FOCO/1=ANDAMENTO/2=PRÓXIMOS/3=OUTROS) e `_grupoDoProjeto(alvo)`.
  │    ⭐ FOCO e PRÓXIMOS são dirigidos pela COR da pasta (configurável em
  │    Configurações → "Foco e Próximos"; padrão foco=amarelo, próximos=verde;
  │    "nenhuma" desliga). **FOCO vence** (checado 1º, mesmo que o projeto
  │    também esteja "em andamento"). As duas cores NUNCA podem ser iguais (a
  │    de um grupo fica bloqueada no seletor do outro). Cabeçalhos FOCO/PRÓXIMOS
  │    pintados com a própria cor; FOCO um tiquinho maior (destaque).
  │    ⚠️ REORDER via `onReorderItem` (Flutter 3.44.7 deprecou `onReorder`):
  │    o callback JÁ entrega `newIndex` ajustado para o item removido — NÃO
  │    aplicar `if (newIndex > oldIndex) newIndex--`. Fazer isso ajustava
  │    DUAS vezes e todo arraste PARA BAIXO virava no-op (a pasta voltava ao
  │    lugar; só subir funcionava). Bug em V0.1.46→V0.1.67, corrigido em
  │    V0.1.68.
  │    ⚠️⚠️ 2ª CAUSA (V0.1.69): NÃO rejeitar por `if (newIndex > fim) return`.
  │    O cartão (60px) é mais ALTO que o cabeçalho da próxima seção (30px);
  │    ao soltar no FIM da seção o SDK devolve o índice DO CABEÇALHO seguinte
  │    (fora de [ini,fim]) e o return fazia a pasta VOLTAR. Como EM ANDAMENTO
  │    é seguida por um cabeçalho, TODO reorder dentro dela travava; OUTROS
  │    (última seção, sem cabeçalho depois) funcionava — esse era o "padrão"
  │    do usuário. Fix: deixar o `dest = (newIndex-ini).clamp(0, len)` cuidar
  │    (arrastar além gruda na BORDA da própria seção, nunca sai dela).
  │    Teste real de arraste: `test/reorder_secoes_test.dart`.
  │    ⚠️⚠️⚠️ CAUSA RAIZ (V0.1.70) — a que realmente resolveu: `_projetos` é a
  │    MESMA referência da lista interna do Storage (carregar() a devolve e a
  │    tela faz `_projetos = p`). `_reordenarComSecoes` fazia `_projetos = [..]`
  │    (REATRIBUÍA p/ lista nova) → quebrava o vínculo → `salvar()` gravava a
  │    ordem ANTIGA do Storage e o `notifyListeners()`→`_aoMudarStorage`
  │    reapontava `_projetos` p/ a interna (antiga) = a pasta VOLTAVA. Sintoma
  │    do usuário: com 1 projeto EM ANDAMENTO, as pastas de OUTROS "não saíam
  │    do lugar". Só quebrava com seções porque o `_reordenar` (lista plana) já
  │    MUTA no lugar (removeAt/insert). FIX: `_projetos..clear()..addAll(nova)`
  │    (mutar no lugar, preservar a referência). Regra geral: reorder/edição
  │    NUNCA reatribui `_projetos`; muta no lugar. Só carregar() da Storage
  │    pode (re)apontar. Teste do widget real: `test/reorder_real_screen_test.dart`.
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
       Tamanho da fonte, Densidade, Projetos em aberto (V0.1.92 — escolhe a
       cores das seções FOCO/PRÓXIMOS), Barra de ferramentas, Backup, Nuvem;
       V0.1.52: NENHUMA seção abre sozinha — a Tema, que ficava aberta, agora
       também nasce fechada; V0.1.54: a folha abre com `isScrollControlled` e
       até 90% da altura da tela — antes ficava baixa e a seção Nuvem, ao
       expandir, caía fora do visível e a rolagem apertava)
```

> **Densidade (V0.1.46):** `Densidade` (Confortável/Compacto) no `TemaController`
> (SharedPreferences `densidade_v1`). Compacto aproxima: cartões da lista
> (bottom 5 vs 10), cabeçalhos, os acessos rápidos (altura 58 vs 68) e as
> caixinhas do projeto (bottom 5 vs 10, padding inferior da lista menor).
> Seletor nas Configurações (SegmentedButton).

> **ConfigSheet fecha arrastando para baixo (V0.1.42):** o
> `showModalBottomSheet` usa `showDragHandle: true` — a alça no topo virou um
> alvo de arraste CONFIÁVEL. Antes o `SingleChildScrollView` do conteúdo
> engolia o gesto e só dava para sair pelo botão "voltar" do Android. A alça
> decorativa manual foi removida (agora vem do próprio showDragHandle).

### Barra de navegação flutuante (`HomeShell`) — V0.1.173
Substituiu a prateleira de acessos rápidos (`_AcessosRapidos`, V0.1.110) E a
função **Recentes**. O app abre no `HomeShell` (`lib/home_shell.dart`): uma barra
inferior com **contorno próprio** (flutua, não cola no fundo; sombra nos temas
com relevo, borda 1px nos planos Terracota/Ônix) sobre um `IndexedStack`.
- **Projetos** → `ProjetosScreen` (lista; sem a prateleira do topo). Abrir um
  projeto empilha `ProjetoScreen` em rota cheia (barra some; volta ao voltar).
- **Muse** (centro, com o `MuseBlob`) → `ConversasScreen` (LISTA de conversas,
  V0.1.173) — só com `ChatConfig.habilitado`. Tocar numa conversa abre o
  `ChatScreen`; o voltar ← do chat retorna À LISTA. "Nova conversa" (✎) começa uma
  limpa (`ChatScreen(iniciarNova: true)`).
- **Estudos** → o projeto reservado "Estudos" (cria se não existir) EMBUTIDO
  (`ProjetoScreen(embutido: true, modoPastasInicial: true)`): nunca sai da rota
  (voltar na pasta→grade; na grade→troca p/ a aba Projetos via `onVoltarNaRaiz`),
  "Excluir" some. É onde o usuário cola trechos da Muse / resumos (a Muse tem
  "Salvar no Estudos": segurar a bolha → menu → `Storage.adicionarNotaEmProjeto`).
- Voltar do sistema: fora de Projetos, volta p/ Projetos; nela, sai do app
  (PopScope do shell; a aba Estudos trata o seu próprio voltar).
- Rastreio de "recentes" em `Storage` (`registrarAbertura`/`recentesIds`) ainda
  existe (sem UI que dependa; `_recarregarRecentes` virou no-op) — pode voltar a
  ter uso futuro sem migração.

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
13. `more_horiz` "•••" (minimizar a caixinha — ESCONDE a barra e deixa só
    as 3 primeiras linhas, com os botões copiar e "•••" no fim da 3ª;
    V0.1.86/V0.1.89)
14. `cleaning_services` (limpar)
15. `delete_outline` (excluir, vermelho)

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
- **Reabertura do teclado (V0.1.38; refinada V0.1.54; robusta V0.1.83):** se a
  caixinha estava sendo editada ao SAIR do app (`_tinhaFocoAoParar`, gravado em
  `inactive`/`paused`/`hidden`), ao voltar (`resumed`) recriamos a conexão de
  entrada com escada verificada 220/520/900ms: a cada tick, só chama
  `TextInput.show` (e `requestFocus` só se o foco foi perdido) se
  `viewInsets.bottom == 0`; se já `> 0`, não mexe. Cancelável por `Timer`
  (`_reabrirTimer`) e por `didChangeAppLifecycleState` ao sair. O texto e o
  cursor ficam intactos (o controlador preserva a seleção).
- ⚠️ **V0.1.83 (fix "subiu e baixou" no desbloqueio facial):** `didChangeMetrics`
  suprime o `unfocus` imediato enquanto `_retomando == true` (janela da escada
  acima). Antes, um `bottom >0 → 0` atrasado do desbloqueio chegava já com o
  app `resumed` e soltava o foco no meio da reabertura → teclado caía no
  instante em que subia; o 2º tick reabria (flicker). `_tinhaFocoAoParar` setado
  em `inactive` mesmo com o IME ainda aberto era o gatilho; agora `_retomando`
  blinda a transição e a escada só mexe se o IME estiver realmente fechado.
- ⚠️ **Histórico V0.1.54 (anti-flicker "sobe e desce"):** o `unfocus()`+
  `requestFocus()` passou a ser atômico dentro de `_reabrirTeclado` (antes o
  `unfocus` imediato no `resumed` e as duas reaberturas só chamavam
  `requestFocus`+`show` — o teclado subia/descia). A 2ª tentativa só disparava
  se a 1ª não reabriu (`somenteSeFechado`).
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
- ⚠️ **`unfocus` IMEDIATO ao esconder (V0.1.63) — HISTÓRICO IMPORTANTE:**
  - V0.1.42: `unfocus()` imediato ao ver `bottom → 0`.
  - V0.1.54/57: virou DEBITADO (`Timer` 320ms) para não desligar o teclado num
    `bottom == 0` passageiro (troca de layout). **MAS** isso criou o bug de
    "minimizar 2-3× com o cursor no fim": o campo focado REABRE a conexão de
    teclado no frame seguinte → `bottom` volta a `>0` → o código cancelava o
    unfocus → nunca soltava. O usuário tinha de minimizar várias vezes.
  - **V0.1.63:** voltou a soltar o foco **IMEDIATAMENTE** no `bottom →
    0` (sem debounce) — sem foco, o teclado não reabre. Para não fechar o
    teclado numa troca de layout transitória, só solta quando **NÃO** há
    composição IME ativa (`_ctrl.value.composing.isCollapsed`) — ou seja, fora
    do meio de uma palavra (esconder o teclado normalmente confirma a
    composição, então o caso comum solta na hora). O `_fecharTecladoTimer` foi
    removido. Testes: `melhorias_test.dart` ("esconder o teclado solta o foco"
    + "teclado NÃO fecha durante composição IME"). **NÃO voltar a debouncear.**
  - **V0.1.83 (atual):** mantém o `unfocus` imediato, mas com janela
    `_retomando` (220–900ms pós-`resumed` com `_tinhaFocoAoParar`): `didChangeMetrics`
    ignora `bottom >0 → 0` durante a escada de reabertura, evitando a corrida
    com o `TextInput.show` do desbloqueio facial. Fora da janela, o
    comportamento do V0.1.63 segue igual. Testes: `melhorias_test.dart` (3 novos
    de V0.1.83: 0 atrasado não solta, reabertura mantém foco, após a janela volta
    a soltar).
- ⚠️ O guard `resumed` é essencial: ao SAIR para outro app o teclado também
  fecha, mas aí queremos PRESERVAR o foco para reabri-lo ao voltar (não brigar
  com `_reabrirTeclado`).
- ⚠️ **Maiúscula não reabre o teclado (V0.1.57):** a correção `maiusculaAposItem`
  (`_debounce`, 2s) fazia `_ctrl.value = …` num campo focado → reabria o teclado.
  Freio: o callback só age com o teclado À VISTA (`viewInsets.bottom > 0` e
  `_foco.hasFocus`); e `didChangeMetrics` cancela o `_debounce` ao esconder.

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

### Minimizar caixinha (botão "•••" — V0.1.86; revisado na V0.1.89)
- O botão `more_horiz` ("•••") da barra alterna minimizar/expandir. Minimizada,
  a caixinha **esconde a BARRA DE FERRAMENTAS** (V0.1.89 — pedido do usuário) e
  mostra só as **3 primeiras linhas** do texto; o resto do conteúdo continua
  intacto.
- **Fim da 3ª linha (V0.1.89):** em vez de reticências, dois botões — **copiar**
  (mesmo ícone `copy_all_outlined` da barra) e **"•••"** (expande de volta, com
  barra e todas as linhas). Implementados por `_BotaoPrevia` (compacto, cabe no
  fim de uma linha) dentro de `_previaMinimizada`.
- O texto é MEDIDO (`TextPainter` em `_textoPrevia`) e cortado numa fronteira
  de palavra para os botões caberem na 3ª linha **sem "…"** (o próprio "•••"
  sinaliza a continuação). O `Text.rich` mantém `maxLines: 3` + `ellipsis` só
  como rede de segurança da medição.
- Estado POR caixinha, salvo no modelo (`Nota.minimizada` — JSON backward-
  compatible: ausente = false; `toJson` omite quando false). É lembrado ao
  fechar o app e viaja em backup/nuvem.
- Na visão minimizada o `TextField` é substituído por uma prévia `Text.rich`
  (mesmo estilo/fonte do campo). Com busca ativa a caixinha é forçada a
  expandir, então o grifo nunca fica escondido. **Tocar na prévia expande.**
- Minimizada esconde o campo de comentário, mas os **títulos dos links**
  continuam visíveis (subcaixinha) — pedido do usuário.
- Com **busca ativa** a caixinha aparece EXPANDIDA (sem alterar o estado
  salvo): a ocorrência pode estar além da 3ª linha.
- Ferramentas que editam/focam o texto expandem antes de agir via
  `_garantirExpandida()` (desfazer, numerar, to-do, OCR, centralizar, limpar,
  editar) — senão a mudança aconteceria com o campo escondido.
- Ao minimizar/maximizar, `_guardarTudo()` derrama o texto da IME antes de
  esconder o campo (mesma proteção do resto do app).

### Senha de projeto — tranca de conveniência (V0.1.93)
- Long-press no projeto → "Editar pasta" → "Proteger com senha" (pede +
  confirma) ou "Remover senha" (exige a senha atual). Guarda só salt + hash
  SHA-256 (`seguranca.dart`); **NÃO** criptografa o conteúdo.
- Abrir projeto trancado (`_abrirProjeto`/`_abrirNota`) passa por
  `_liberarAbertura`: pede a senha e compara o hash; errou/cancelou = não abre.
- Projeto trancado é EXCLUÍDO da busca de conteúdo (`_resultadosBusca` faz
  `if (p.temSenha) continue`); o NOME ainda pode aparecer (abrir por lá pede a
  senha). Cartão mostra 🔒 ao lado do nome.
- ⚠️ Por design, o backup/export e o "Copiar tudo" incluem TUDO (inclusive
  projetos trancados) — é o caminho de recuperação se a senha for esquecida
  (coerente com a REGRA DE OURO de nunca perder conteúdo).

### Lembrete semanal de backup (V0.1.93)
- Configurações → Backup → "Lembrete semanal de backup" (toggle + dia + hora).
  `LembretesService.configurarBackupSemanal` agenda uma notificação RECORRENTE
  (`matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime`, id fixo
  `_idBackupSemanal = 900001`). Só NOTIFICA para você lembrar — NÃO faz backup
  sozinho (a nuvem segue 100% manual). Reagenda no `init()` se estiver ativo.

### Atalho "Nova nota" ao segurar o ícone (V0.1.93)
- `quick_actions` registra o App Shortcut `nova_nota` em `_configurarAtalhos`
  (initState da home). Ao disparar, `_novaNotaRapida` abre o projeto "Notas
  rápidas" (cria se não existir) com `ProjetoScreen(adicionarAoAbrir: true)`,
  que no initState cria uma caixinha nova em Tarefas e foca nela. Funciona no
  cold start: recarrega `Storage` antes de criar/abrir.

### Arrastar caixinha para a esquerda = excluir (V0.1.92)
- Cada caixinha da lista (`ReorderableListView` em `projeto_screen.dart`) é
  envolvida num `Dismissible` (`direction: endToStart`, fundo vermelho com
  lixeira) cujo `onDismissed` chama o `_excluir(aba, i)` já existente — ou
  seja, **com "Desfazer"** (SnackBar) e com o espelho de "em andamento".
- O `Dismissible` é o widget de TOPO do item e carrega a `ValueKey(nota.id)`
  (que o `ReorderableListView` exige). O reorder continua saindo do pino
  interno (`ReorderableDragStartListener`), então swipe (horizontal) e
  reordenar (pino) não brigam — mesmo arranjo já usado nos cartões de projeto
  da home (`_arrastavel`).

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
- ⚠️ **Excluir PROJETO (V0.1.65):** único caminho = `_excluirComUndo` (home) — sem
  diálogo, com **Desfazer**. Dois gatilhos: (1) **arrastar a pasta para a
  esquerda** na home (`Dismissible`/`_arrastavel`, envolve o cartão nos dois
  branches — neumórfico e plano); (2) botão **excluir DENTRO do projeto**
  (`projeto_screen`, na linha do nome, junto de PDF/Copiar) que CONFIRMA e devolve
  `'excluir'` no `Navigator.pop` → `_abrirProjeto`/`_abrirNota` chamam
  `_excluirComUndo`. O botão de excluir SAIU da linha da pasta na home.
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
  do último projeto passa (`liberarEsvaziamento()` chamado em `_excluirComUndo`).
  Impede que um bug/versão nova "abra vazio e grave por cima".
- **Google Drive:** `AndroidManifest.xml` com `allowBackup="true"` +
  `fullBackupContent="@xml/backup_rules"` + `dataExtractionRules` — o Android
  sobe os dados do app para a conta Google e RESTAURA ao reinstalar.
  ⚠️ Antes da V0.1.42 o atributo não existia e, com targetSdk 36, o backup do
  Google ficava DESLIGADO por padrão (perda irreversível ao desinstalar).
- **⚠️ SharedPreferences EXCLUÍDAS do backup (V0.1.119) — NÃO re-incluir.** As
  duas regras de backup (`xml/backup_rules.xml` p/ Android ≤11 e
  `xml/data_extraction_rules.xml` p/ Android 12+) agora EXCLUEM
  `FlutterSharedPreferences.xml`; só os ARQUIVOS (projetos) continuam no backup.
  **Causa:** o histórico LOCAL da Muse (chat) vive nas SharedPreferences; o Auto
  Backup sobe um snapshot ~diário e, ao reinstalar/transferir/auto-restaurar, o
  Android RESTAURAVA um snapshot ANTIGO POR CIMA do local → as conversas de hoje
  sumiam e a "última" voltava para dias atrás (sintoma relatado: "última conversa
  é de 13/10"). O merge no app (V0.1.118) NÃO defende disso — o SO troca o
  arquivo inteiro embaixo. Trade-off aceito: tema/lembretes/barra deixam de ter
  backup na nuvem (locais e re-configuráveis); projetos ficam intactos (arquivos).
  Mesma família do incidente 2026-08-22 (desinstalar restaurava estado antigo).

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
  barra de status): campo de texto + DUAS linhas de `ActionChip`s de tempo
  (30 min · 2 h · 4 h · 24 h).
- ⚠️ **Duas linhas de tempo (V0.1.65):** a **1ª linha** agenda DIRETO ao tocar
  (`_agendar`), e tem o chip **"Outro"** (tempo exato via diálogo, `_outro`) ao
  lado do 24 h — readicionado na V0.1.66 (lembrete rápido preciso). A **2ª linha**
  (chips com "+" e cor de accent) **SOMA** em `_somado` (`Duration`); abaixo
  aparece um resumo "Daqui a X" + data/hora com **dia da semana por extenso**
  (V0.1.87/88: ex. "22/09 • 09:00 • Terça-feira", via `quandoComDiaSemana` em
  `lembretes.dart`; a pedido do usuário NÃO abreviar — pode quebrar para a 2ª
  linha) com **Limpar** e **Salvar**
  (`_salvarSomado`).
- ⚠️ **`_agendar` à prova de falha (V0.1.66):** retorna `Future<bool>` e usa
  `try/catch/finally` — o `finally` SEMPRE rearma `_agendando` (o botão nunca
  fica travado em cinza) e um erro de `zonedSchedule`/permissão vira um diálogo
  copiável (`_mostrarErroAgendar`). `_salvarSomado` só zera `_somado` se
  `_agendar` retornou true. Bug anterior (V0.1.65): se `agendar()` lançava, o
  `_agendando` ficava true → Salvar cinza para sempre e o lembrete não ia.
- ⚠️ **Ícone da notificação (V0.1.65):** `@drawable/ic_notif` (um "T" vetorial,
  silhueta branca) em vez de `@mipmap/ic_launcher` (que virava um quadrado na
  barra de status). Referenciado nos dois `AndroidInitializationSettings` (init
  foreground e background) e em `AndroidNotificationDetails(icon:)`.
- ⚠️⚠️ **`ic_notif` PRECISA de referência no manifesto (V0.1.67):** como ele é
  usado só por STRING em runtime (não via `R.drawable` no código), o build de
  RELEASE o REMOVIA (shrink de recurso "não usado") → `PlatformException(
  invalid_icon, resource ic_notif could not be found)` = notificações
  QUEBRADAS. Confirmado: no `resources.arsc` do APK v0.1.66, `ic_launcher`
  aparecia e `ic_notif` NÃO. Fix: um `<meta-data android:resource=
  "@drawable/ic_notif">` no `AndroidManifest.xml` cria uma referência ESTÁTICA
  (como o `android:icon="@mipmap/ic_launcher"`), mantendo o recurso no APK.
  **Regra:** qualquer drawable usado só por nome em runtime precisa ser
  referenciado no manifesto (ou num `res/raw/keep.xml`).
- **Busca da home acha lembretes (V0.1.65):** `_resultadosBusca` também casa
  `LembretesService.pendentes` por `texto` → seção "LEMBRETES"
  (`_cartaoLembreteResultado`, toca → abre a folha). Sem busca separada dentro
  dos lembretes.
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

### Chat com IA (V0.1.95) — módulo ISOLADO `lib/chat/`
Janela de chat com uma IA (gateway **OpenCode Go**, modelo `muse-spark-1.3-contributor`
com fallback) para discutir projetos; preset **Coach** = treinador do Calis Timer (vê o
desempenho do usuário). Aberto pela caixinha **ASSISTENTE** dos acessos rápidos da home
(ver `_AcessosRapidos`) — só aparece com o recurso ligado (flag `CHAT`). Até V0.1.109 era
um `FloatingActionButton.small` à esquerda do "+"; migrado para a caixinha em V0.1.110.

- **Separação (para um dia publicar na Play SEM o chat):** todo o chat vive em `lib/chat/`
  (`chat_config`, `chat_models`, `chat_service`, `chat_store`, `chat_screen`). O resto do app
  só o referencia em `projetos_screen.dart` (o botão), **atrás da flag** `ChatConfig.habilitado`.
  A flag é de COMPILAÇÃO: `--dart-define=CHAT=true` + `--dart-define=TASKIX_CHAT_URL=...`.
  Build sem esses defines = **sem chat** (botão nem existe; teste cobre isso em `chat_test.dart`).
- **Segurança (a chave do OpenCode NUNCA vai no APK/repo):** o app fala com um **proxy na VPS**
  (`/opt/taskix-chat/`, FastAPI, systemd, Caddy em `/taskix/*`) que guarda a chave. Auth = o
  **ID token do Firebase** do usuário logado (reusa `SyncService.entrarComGoogle`); o proxy
  valida o token (projeto `adm-projetos-f78e9`) e só aceita a conta do DONO (`OWNER_EMAILS`).
  Repo pode ser público — o APK não tem segredo utilizável. `TASKIX_CHAT_URL` vai por secret do CI.
- **Modo no título + capitalização (V0.1.96):** a AppBar mostra o modo ativo ("Chat · Conversa"
  / "Chat · Coach Calis"); o campo de texto usa `TextCapitalization.sentences`; o proxy capitaliza
  o início das frases da resposta da IA (`_cap_frases`).
- **Coach / Calis Timer:** no preset Coach, o proxy lê o desempenho do usuário no Firestore do
  projeto `calis-timer` (`users/{uid}`, SOMENTE leitura/GET) via service account e injeta um
  resumo RICO no prompt: planos (séries×reps×carga), evolução da progressão por exercício,
  check-ins por dia, conclusões e troféus, com um cabeçalho "como ler" (`calis_resumo.py`).
  Depende de 1 passo manual (colocar `calis-timer-sa.json` na VPS); sem ele, o coach pede ao
  usuário que descreva o treino (degradação graciosa). Detalhes no proxy: `calis_resumo.py`.
- **Conversa / projetos (V0.1.97):** no preset Conversa, o proxy injeta
  `/opt/taskix-chat/projetos.md` — um resumo CURADO e compartilhável dos projetos do usuário —
  para a IA responder perguntas básicas sobre eles. ⚠️ **FLUXO:** ao shipar uma funcionalidade
  importante em QUALQUER projeto, atualizar esse arquivo (curado, **sem** segredos/chaves/infra/
  estratégias de trading — vai para o gateway externo). Ver memória `feedback_muse_chat_projetos_md`.
- **Capitalização (V0.1.97):** o que o usuário envia é forçado a começar cada frase com maiúscula
  (`capitalizarFrases` em `chat_models.dart`); a resposta da IA também (no proxy, `_cap_frases`).
- **Muse + histórico (V0.1.98):** o assistente se chama **Muse** (título "Muse · <modo>", botão
  "Muse"). Histórico de conversas LOCAL (`Conversa` em `chat_models.dart`; `ChatStore` guarda
  várias conversas na chave `taskix_muse_convs_v1`, migra a antiga `taskix_chat_v1`). Na AppBar:
  ícone de histórico (abrir/apagar conversas), nova conversa, e o seletor de modo. Abre no modo
  **Coach** por padrão. No proxy, o Coach é **proativo** (elogia ganhos, aponta estagnação com
  "há N dias", sugere próximo foco, comenta empurrar×puxar) e o resumo traz "último recorde há Nd".
- **3 modos + UX (V0.1.99):** presets **Coach Calis** · **Projetos** (injeta `projetos.md`) ·
  **Geral** (neutro, sem contexto — pessoal/psicólogo; prompt com CVV 188 p/ crise). `ChatPreset`
  renomeou `livre`→`projetos` (migração em `deId`). **Segurar a bolha copia a mensagem inteira**
  (`Clipboard` + snackbar; `Text`, não `SelectableText`). O "pensando…" tem **contador
  segundos.décimos** (`Timer` 100ms). Memória da conversa: o proxy envia as mensagens recentes
  que cabem em `HISTORY_CHARS` (~24k chars).
- **V0.1.100:** o Muse **reabre a ÚLTIMA conversa** usada (`ChatStore.marcarUltima/ultimaId`,
  chave `taskix_muse_ultima_v1`; salva no `dispose`). O **título do topo = nome da conversa**
  (fonte 14, até 2 linhas). **Segurar uma conversa no histórico = renomear.** Atalho do **Muse
  dentro do projeto**: botão à esquerda do "ver como pastas" em `projeto_screen.dart` (gated por
  `ChatConfig.habilitado`).
- **V0.1.101:** conhecimento do Muse reorganizado na VPS em `/opt/taskix-chat/conhecimento/`
  (`projetos.md` → modo Projetos; `pessoal.md` → modo Geral; `INSTRUCOES.md` = guia p/ outra IA/
  usuário editar via Termius, com DATAS `[AAAA-MM-DD]`). O proxy injeta a **data de hoje** (pt-BR).
  App: **anexo (clip)** no campo de texto (colar texto ou arquivo via `file_picker`; vai junto da
  mensagem); lista **invertida** (`reverse:true`) — sempre abre na mensagem mais recente; **renomear
  reflete no título na hora**.
- **V0.1.102 — modelo + TTS + resumo:** ⚠️ **`muse-spark` saiu do ar** (gateway devolve 400
  `ModelProtocolUnsupported`); o Muse agora usa **DeepSeek**. Seletor de **modelo** por conversa
  (menu ⋮): **Rápido** = `deepseek-v4-flash-vision-exp` (padrão, com visão) · **Caprichado** =
  `deepseek-v4.1-flash` (+ elaborado, + lento). `.env`: `OPENCODE_GO_MODEL`/`OPENCODE_FALLBACK`/
  `MAX_TOKENS=3500`; proxy aceita `model` (allowlist `MODELOS_OK`). Trocar de modelo no meio da
  conversa funciona (o histórico é reenviado, o novo modelo lê tudo). **Botão de ÁUDIO** (TTS
  `flutter_tts`, pt-BR) no canto da bolha da IA. **Resumo da conversa** (menu ⋮ → preset `resumo`
  no proxy) p/ colar em outra IA. Banner do Coach encurtado p/ "Modo Coach Calis Timer".
- **V0.1.103 — imagem (visão) + voz + contexto IA:** clip → **Anexar imagem** (`image_picker`,
  base64); o app manda `imagem_b64`, o proxy embute na última msg (formato vision OpenAI-compat)
  e **força o modelo com visão** (`deepseek-v4-flash-vision-exp`). **TTS escolhe voz FEMININA
  pt-BR já instalada** (não baixa; pitch 1.08). Novo arquivo de conhecimento
  `conhecimento/contexto_ia.md` (mundo da IA 2024→hoje, curado/editado — a IA NÃO navega na web)
  injetado no modo **Geral** (junto do `pessoal.md`).
- **V0.1.104 — contexto IA no Projetos:** `contexto_ia.md` também injetado no modo **Projetos**.
  Endpoint do gateway = **OpenCode Zen Go** (`opencode.ai/zen/go/...`); DeepSeek flash = faixa
  barata/grátis (por isso o usage mostra ~0).
  ⚠️ **YouTube REMOVIDO na V0.1.108** (app + proxy `/youtube` + `youtube.py` + cookies + yt-dlp/
  deno): o YouTube bloqueia o IP da VPS ("Sign in to confirm you're not a bot") mesmo com cookies
  válidos — só funcionaria com proxy residencial. **Não reintroduzir** sem um proxy. Fluxo do
  usuário agora: ele cola no Muse o resumo que o Gemini faz do vídeo e debate.
- **V0.1.105:** App Shortcut (segurar o ícone) ganhou **"Muse (última conversa)"** além de "Nova
  nota" (`QuickActions` em `projetos_screen.dart`, gated por `ChatConfig.habilitado`). Conhecimento
  do Muse ampliado em `conhecimento/contexto_ia.md` (famílias de modelos Claude/GPT/Gemini +
  sistemas agênticos, curado/datado).
- **V0.1.106:** **Busca dentro da conversa** (lupa na AppBar): grifa as ocorrências e pula até
  elas (`scroll_to_index` + `AutoScrollTag`; ▲/▼ e contador i/N). (Servidor) `MAX_TOKENS=8000`
  (respostas longas, ex.: resumir 10 livros, não cortam mais). Contexto de entrada é grande:
  testado o modelo lendo ~100k chars e achando uma palavra no fim — arquivos de conhecimento
  (KB) são triviais.
- **V0.1.108 — voz neural pt-BR:** o botão de áudio tenta primeiro a **voz neural feminina
  pt-BR** (`pt-BR-FranciscaNeural`, Microsoft Edge, sem chave e sem custo) via novo endpoint
  do proxy **  `POST /taskix/tts`** (`app.py`, teto 3000 chars/pedido; `requirements.txt` ganhou
  `edge-tts` + `gTTS`). Cascata no servidor: **Piper local primeiro** (neural pt-BR
  `pt_BR-faber-medium`, offline em `/opt/taskix-chat/vozes/`, ~2–3 s p/ frase curta —
  sempre a mesma voz, sem depender de IP); Edge depois; Tradutor em pedaços de ~90 chars;
  se tudo falhar, 502 e o app usa o TTS local sem erro visível. (Edge dá 403 no IP da VPS
  desde 2026-10-12; Kokoro-82M foi avaliado e descartado: 15 s p/ 6 s de áudio em 1 vCPU.) App: `ChatService.audioNeural` busca o MP3 e toca com `audioplayers`
  (ampulheta ⌛ enquanto gera, ~2–5 s); qualquer falha cai em silêncio para o TTS local
   (`flutter_tts`, que continua como fallback). Caddy não mudou (`/taskix/*` já cobre a rota).
- **V0.1.109 — persona Muse Spark:** a assistente agora tem nome (**Muse Spark**), gênero
  **feminino** (fala de si no feminino), é **especialista em neurociência e escritora** e tem tom
  **amigável/elogioso/motivador com crítica honesta** (elogio + contraponto, fecha positivo e na
  maioria das vezes com pergunta propositiva). Servidor: bloco `_PERSONA` em `app.py` via `_IDENT`
  (vale nos 3 modos; `INSTRUCOES.md` documenta que personalidade mora no código). App: textos
  visíveis ("Muse (assistente)", atalho, hints) viraram "Muse Spark" no feminino. Voz neural já era
  feminina (FranciscaNeural/Piper faber) — combina.
- **V0.1.111 — scroll mostra o "pensando":** ao enviar, a tela descia só até a msg enviada e o
  "pensando… Ns" ficava escondido embaixo (parecia travado). Causa: o "pensando" é um item EXTRA
  (`itemCount = n+1`) sem `AutoScrollTag`, e o `_rolarFim` mirava `n-1`. Fix: tag `pensando` no
  índice n + `_rolarFim` mira `n` enquanto `_enviando` (volta a `n-1` ao abrir e ao chegar a resposta).
- **V0.1.112 — abre direto + resposta começa do início:** abrir o chat animava o scroll pela
  conversa toda (250ms do topo ao fim). `_rolarFim` ganhou flags: `instantaneo` (1ms — o pacote
  proíbe duração zero) e `inicioResposta` (`begin` em vez de `end`). Abrir = instantâneo na 1ª
  linha da última resposta (com msg sua por último, mostra o fim); resposta nova = animado até a
  1ª linha dela. Envio (pensando) e busca (meio) inalterados.
- **V0.1.113 — seletor de TAMANHO da resposta:** novo `enum ChatTamanho {longo, curto}`
  (`chat_models.dart`), guardado POR conversa (como `modelo`/`preset`; JSON compat: ausente =
  `longo`), escolhido no menu **⋮** (divisor abaixo dos modelos, check no ativo). O app manda
  `tamanho` no `/chat`; o proxy, no modo **curto**, acrescenta `_CURTO` ao system — pede ~METADE
  do tamanho, SEM cortar (obriga concluir o raciocínio e terminar as frases) e mantendo o tom
  motivador/propositivo. **`MAX_TOKENS` (12000) NÃO muda:** é só teto — a brevidade vem do
  prompt, então a resposta encolhe mas nunca trunca. Padrão = **longo** (comportamento atual
  preservado). `curto` não vale p/ o preset `resumo` (tem alvo próprio). Teste em `chat_test.dart`.
- **V0.1.114 — horário + banner modo/tamanho:** (1) **Noção de horário:** o proxy manda
  data+HORA de Brasília + período (`_hoje` → "terça-feira, 13 de outubro de 2026, 08:35 da manhã")
  com ordem explícita de usar para saudações e "ontem à noite/hoje/amanhã" (nunca boa-noite de
  manhã); o app manda `hora` (ms) por mensagem e o proxy prefixa `[dd/MM HH:mm]` no histórico —
  custo de ~15 chars/msg, sem lentidão. Compat: sem `hora` = sem prefixo. (2) **Timestamp na tela:**
  `_rotuloHora()` embaixo da bolha (hoje `HH:mm`, ontem `ontem HH:mm`, senão `dd/MM HH:mm`;
  fora do Copiar). (3) **Banner sempre:** `Modo Calis • Longo` / `Modo Projetos • Curto` /
  `Modo Geral • Curto` (preset+tamanho atuais, atualiza ao trocar); `ChatPreset.coach` encurtou
  o rótulo `Coach Calis`→`Calis`; histórico mostra   `preset · tamanho · data`.
- **V0.1.115 — chat não perde mais mensagens ao sair/voltar:** causa era dois
  `salvar` concorrentes (leitura-modificação-gravação): o mais lento sobrescrevia o
  mais novo — ex.: salvar da resposta chegava antes do salvar da pergunta. Fix:
  `ChatStore` com fila FIFO (`_fila`; `salvar`/`remover` encadeiam) + snapshot via
  JSON na hora da chamada (o corte de 120 msgs vale só na cópia, sem mutar a tela).
  Tela passa a esperar (`await`) os saves no envio, troca de modo/modelo/tamanho e
  histórico; o `dispose` (que não pode esperar) vira só reforço. Teste de regressão
  em `chat_test.dart` ("saves concorrentes não perdem mensagens").
- **V0.1.116 — até 3 imagens por mensagem:** o clip passa a usar `pickMultiImage` (lista
  `_imagensB64`, máx. 3; chip por imagem com X individual; aviso ao estourar). O app manda
  `imagens_b64` (lista) e o proxy embute as 3 como `image_url` + força o modelo de visão.
  Compat: o proxy ainda aceita o `imagem_b64` único do APK antigo. Servidor reiniciado junto.
- **Busca na internet SOB DEMANDA (servidor, sem APK novo):** novo `busca_web.py` no proxy
  (Tavily; chave `TAVILY_API_KEY` no `.env` do serviço — plano grátis 1.000 buscas/mês). Só
  pesquisa quando o usuário PEDE na mensagem ("pesquise na internet…", "veja no site…",
  "pesquisa pra mim…"); injeta um bloco datado "RESULTADOS DE BUSCA NA INTERNET" naquela
  resposta (teto 5 resultados/~4.5k chars, cache de 12h por termo). Sem chave/falha = fica
  desligada ou a IA avisa e segue com o que sabe. Fora do pedido, o Muse continua sem internet
  (o `contexto_ia.md`/`INSTRUCOES.md` documentam). Custo: ~1 chamada HTTPS + bloco pequeno só
  na resposta pesquisada.
- **Novidade científica do dia (servidor, sem APK novo):** novo `novidade.py` — 1x/dia, só
  entre 09–19h (Brasília), na 1ª mensagem da janela ainda sem novidade. Tópicos giram por
  data (neurociência, hipertrofia, atividade física, sono… — editável em `TOPICOS`); títulos
  já usados não repetem (estado em `/var/lib/taskix-chat/novidade.json`, escrita liberada via
  `ReadWritePaths` no systemd). Bloco curto (~1,5k chars) manda encaixar só se couber no
  assunto, senão citar de passagem. Custo: 1 busca Tavily/dia + bloco em 1 resposta/dia;
  sem chave/falha/fora da janela = desligada sozinha. Testes em `tests_novidade.py`.
- **V0.1.117 — atalho "Muse Spark" curto:** o App Shortcut ao segurar o ícone perdeu o
  sufixo "(última conversa)" — agora é só "Muse Spark" ("Nova nota" intacto; o destino
  continua abrindo na última conversa).
- **V0.1.122 — voz feminina dii + modo áudio + leitura por frase:** (1) **Voz:** o `/tts` do
  proxy passou do **faber (masculino)** para a **dii** (FEMININA pt-BR, comunidade
  `csukuangfj/vits-piper-pt_BR-dii-high`, em `/opt/taskix-chat/vozes/`), com **`length_scale 1.10`**
  no `.onnx.json` (~10% mais lenta, sem robotizar); faber vira **reserva** (`PIPER_VOZ_FALLBACK`).
  Edge segue bloqueado (403) e Kokoro foi descartada (RTF>1 em 1 vCPU). (2) **Modo áudio
  (`_modoAudio`):** SEGURAR o botão enviar alterna — o ícone vira 🎤 e a resposta da Muse **toca
  sozinha** (semi-conversação: você dita no Gboard, ela responde em texto+voz). (3) **Leitura por
  FRASE (streaming):** `_falar` quebra a resposta em frases (`_dividirFrases`, corta após .!? +
  espaço), toca a 1ª assim que chega e **prefetcha** a próxima durante a reprodução (início ~1–1,5 s;
  Piper ~5× mais rápido que o tempo real = sem buraco). Cancelamento via `_falaToken`; fallback
  `flutter_tts` por frase se a neural falhar. ⚠️ A voz NÃO fica residente (subprocess por chamada =
  zero RAM parada; modelo de ajuste só em teste, removido depois).
- **V0.1.123-125 — afinação da voz dii:** +velocidade (`length_scale` 1.10→1.02), carimbo de
  data/hora NÃO vaza mais (servidor `_sem_carimbo` + app `_semCarimbo`, some da escrita e da fala),
  pausa de ponto curta (`--sentence_silence 0.05` ≈ vírgula), parágrafos colados na fala (`\n+`→espaço),
  e a leitura voltou a ser **1 clipe** (prosódia natural, sem emendas). Dicionário de **pronúncia**
  (`PRONUNCIA_FALA` no proxy; ex.: bike→"báik") — só afeta a fala, não a escrita.
- **V0.1.126 — STREAMING (fala enquanto escreve) + modo áudio por frase:** novo endpoint
  **`/chat_stream`** (SSE) no proxy: `_montar_contexto` (prompt COMPARTILHADO com `/chat`) +
  `_call_gateway_stream` (gateway com `stream:true`) emite FRASES conforme gera; o app
  (`ChatService.enviarStream`/`MuseEvent`) consome no serviço (sobrevive ao voltar) e salva via
  `anexarIa` ao terminar. A tela mostra a resposta AO VIVO (`_bolhaStream`) e, no modo áudio, fala
  **por PARÁGRAFO** (V0.1.127: `MuseEvent.fimParagrafo`; `/chat_stream` marca `p` quando há linha em
  branco — `_cortar_frase` com lookahead). Falar por parágrafo (não por frase) dá entonação de
  PERGUNTA correta + sem vão interno; só pausa (natural) ENTRE parágrafos. Começa após o 1º parágrafo.
- **V0.1.128 — início + sem vão:** a 1ª FRASE sai imediatamente (`_primeiroChunkVoz`, início ~1s em vez
  de esperar o 1º parágrafo fechar; costuma ser saudação) e `_bombearFila` faz PREFETCH do áudio do
  próximo parágrafo enquanto toca o atual (acaba o vão entre parágrafos). ⚠️ Limite físico: em resposta
  curta/rápida o texto termina antes de a voz conseguir sair (síntese leva ~1s); overlap real só em
  respostas longas. Reduzir mais = manter o Piper residente (não feito: custa RAM na VPS).
- **V0.1.129 — fila de voz PRODUTOR-CONSUMIDOR (mata os vãos):** o bug era a fila sintetizar o
  próximo trecho só DEPOIS que o atual acabava de tocar → vão de ~2-3s entre frases/parágrafos, e o
  replay sintetizava a mensagem INTEIRA antes de tocar (~10s em resposta longa). Agora dois workers:
  `_vozSintese` (sintetiza um trecho por vez, ADIANTADO) + `_vozPlay` (toca em ordem). Como o Piper é
  5× realtime, o próximo fica pronto antes de o atual acabar = sem vão. **Replay (`_falar`) agora toca
  por PARÁGRAFO** (começa após o 1º, não a msg toda). Pronúncia: +delay→"delei".
- **V0.1.130 — vão de linha curta + auto-enviar por voz:** (1) trecho de voz só é falado quando o
  parágrafo fecha E tem ≥80 chars — uma 1ª linha/título curto JUNTA com o próximo numa fala só (antes
  "secava" e dava vão grande antes do 2º parágrafo); removido o `_primeiroChunkVoz`. (2) **Auto-enviar
  no modo áudio** (`_aoDigitarVoz` + `_autoSendTimer`): ao ditar pelo teclado de voz (Dictate/Whisper/
  Gboard), quando o texto para de mudar por ~1,5s (soltou o mic), ENVIA sozinho → semi-conversa
  hands-free (dita→envia→responde falando). App não recebe o evento do mic do teclado; por isso é
  por PAUSA. Só no modo áudio; fora dele, envio normal no botão.
- **V0.1.131 — VOZ ON-DEVICE (sherpa-onnx, offline):** a síntese sai da VPS de 1 vCPU (gargalo dos
  ~7s) e vai pro PRÓPRIO CELULAR. `lib/chat/tts_ondevice.dart` (`TtsOnDevice`): baixa 1x o modelo
  dii (`vits-piper-pt_BR-dii-high.tar.bz2`, ~67 MB, do release tts-models do sherpa-onnx), extrai
  (`archive`: BZip2+Tar → `extractArchiveToDisk`) p/ `<docs>/tts_dii/`, carrega `OfflineTts` (vits,
  lengthScale 1.02). `sintetizar()` → WAV (Float32→PCM16). A fila de voz tenta on-device primeiro
  (`_sintetizarTrecho`); se não pronto/falhar, cai no `/tts` da VPS (reserva). Normalização de
  pronúncia replicada no cliente (`_normalizarFala`: NxM→"N de M", bike→báik, delay→delei, rep→…)
  porque on-device não passa pelo servidor. `preparar()` ao ligar o modo áudio / tocar o alto-falante
  (download em 2º plano; até ficar pronta usa o servidor). **Build:** deps `sherpa_onnx`+`archive`;
  `abiFilters = arm64-v8a, armeabi-v7a` no build.gradle.kts (sem x86 p/ não inflar o APK). ⚠️ Síntese
  no isolate principal (jank leve ~0,5-1s/parágrafo; corre adiantada à fala). Modelo NÃO embutido (baixado).
- **V0.1.132 — ajustes + 📘 DOC MESTRE `MUSE.md`:** (1) velocidade da fala −2% (length_scale 1.02→
  **1.04**, nos DOIS lados: `vozes/pt_BR-dii-high.onnx.json` no proxy + `_lengthScale` em
  `tts_ondevice.dart`); (2) **auto-enviar** por voz mais rápido (1500→**600 ms**); (3) sono **sexta e
  sábado** mais tarde (sinal ≥21:30, enfático ≥22:00; seg-qui inalterado; `_nivel_sono` no `app.py`);
  (4) perfil: +2 halteres de 2 kg (`conhecimento/perfil.md`); (5) pronúncia **halter→"altér"**,
  **halteres→"altéres"** (nos dois lados); (6) **nome sem pausa de vírgula** ("boa noite, Vinícios" →
  fala "boa noite Vinícios"; regex nos dois lados). (7) **Criado `MUSE.md`** (raiz do repo): guia
  COMPLETO p/ qualquer IA/agente — voz/repo/download, onde mudar VELOCIDADE e PRONÚNCIA (sempre 2
  lugares), sílaba tônica, Dictate+auto-enviar, memória/conhecimento/modos, checklist de contribuição.
  **➜ Ao mexer na Muse, comece pelo `MUSE.md`.**
- **V0.1.133/134 — pronúncias + botão de GRAVAÇÃO no app:** arrego→"arrêgo", kg→"quilos",
  despedidas naturais, auto-enviar 0,4s. **V0.1.134:** botão 🎤 push-to-talk na barra de entrada
  (`speech_to_text`, voz nativa do Android/Google = instantânea; `_micStart`/`_micStop`; segura-fala-
  solta-envia). Mantém o botão de enviar manual. Perm. RECORD_AUDIO + queries RecognitionService.
- **V0.1.135 — BOTÃO ÚNICO (toque=enviar / segurar=voz):** mic e enviar viraram um só. Toque curto
  envia o texto digitado (resposta em texto); SEGURAR grava por voz e, ao soltar, envia + resposta
  FALANDO (voz→voz). Auto-play passa a seguir o método de entrada (sem modo-áudio-toggle nem
  auto-enviar-por-pausa, removidos). Ver MUSE.md §6.
- **V0.1.136 — pronúncias app/foram:** `app`→"ép", `apps`→"éps", `foram`→"fôram" nos DOIS lados
  (`PRONUNCIA_FALA` no proxy + `_normalizarFala` no app). `\b` protege `WhatsApp`.
- **V0.1.137 — voz longa não envia sozinha:** gravação TRAVADA (segurar inicia, soltar NÃO para).
  Causa: a caixa crescia e o FAB deslocava de baixo do dedo → `onLongPressEnd/Cancel` → envio
  parcial. Fix: `Row(end)` ancora o botão embaixo + `End/Cancel` viram no-op; concluir é TOQUE
  no enviar, X cancela mantendo o texto p/ editar. Remove `_micSegurando`.
- **V0.1.138 — segurar voltando a abrir o mic:** regressão da V0.1.137 — o `tooltip:` posto no FAB
  (`Parar de ouvir/Enviar`) faz o `Tooltip` consumir o long-press e o `onLongPressStart` do
  `GestureDetector` nunca disparava (a própria V0.1.137 avisava "sem tooltip"). Fix: SEM tooltip
  no FAB + `behavior: translucent` + ícone volta a `mic` gravando / `send` parado.
- **V0.1.139 — gravar de 1ª + teclado não cobre:** (1) Some o snack "voz offline pronta" (vira
  pré-aquecimento silencioso em `initState` p/ STT+TTS); `_micStart` dá feedback imediato
  (vermelho na hora, antes do `initialize`) — 1º segurar já grava, sem 2º clique. (2) Teclado/
  caixa crescendo escondia o fim: `didChangeMetrics` + foco + `onTap/onChanged` chamam
  `_rolarFim` (ditado usa `instantaneo`), última mensagem fica acima do teclado/caixa.
- **V0.1.140 — caixa acompanha o ditado:** o TextField 1→5 linhas ganhava scroll interno mas a
  atualização programática (`_ctrl.text = ...`) não descia sozinha — após 5 linhas o texto novo
  ficava escondido embaixo. Fix: `ScrollController` próprio (`_caixaScroll`) + `_rolarCaixaFim`
  (jump ao fim) a cada parcial do ditado, no `onChanged` e no `onTap`.
- **V0.1.141 — X limpar + atalho Muse sem fantasma:** (1) X dentro da caixa (`suffixIcon`,
  `ValueListenableBuilder`) limpa texto+anexo+imagens; se gravando, para sem enviar e mantém
  o foco. (2) Segurar o ícone → Muse: mostrava a lista de projetos por 1-2s com fantasma do
  chat (cold start + push). Fix: `_museAberto` vira loading (`setState` imediato + body troca
  p/ `CircularProgressIndicator`) até o `ChatScreen` empilhar.
- **V0.1.142 — ditado longo não corta:** o recognizer parava sozinho em pausa (~3s) ou teto
  de sessão e o texto truncava no meio da frase (`cancelOnError:true` + sem restart +
  sobrescrevia `_ctrl.text`). Fix: ditado CONTÍNUO — `listenFor:120s` + `pauseFor:8s` (em
  `SpeechListenOptions`) + `cancelOnError:false`; `_aoStatusStt` recomeca sozinho acumulando
  em `_textoBase`; `_paradaManual` distingue sistema (recomeça) de usuário (enviar/X/limpar).
- **V0.1.143 — transcrito não volta após envio:** o `stop()` entrega um onResult final DEPOIS
  de limpar/enviar e ele repovoava a caixa vazia (aparecia no meio da resposta da Muse).
  Fix: `_sessaoVoz` — cada segurar gera id novo, cada parada invalida; onResult/status com
  id velho são descartados (o final dentro da janela de 350ms ainda vale).
- **V0.1.144 — Muse abre sem flash:** pré-aquece o histórico (`ChatStore.aquecer()` no start
  do app) + cache em memória de `listar()` validado pelo string do disco (só leitura; gravadores
  seguem lendo o disco) — a 1ª abertura não pisca ~1s no loading.
- **V0.1.145 — acessos com desenho 05 da galeria:** caixinhas RECENTES/ASSISTENTE/ESTUDOS
  viram fundo escuro fixo (`#0C0C0D`) + desenho traçado na cor de acento do tema (`app.fab`,
  então cada tema pinta com a sua cor). `_GlifoAcesso`/`_GlifoPainter` (`CustomPainter`,
  mesma geometria 96x96 dos SVGs): relógio, robô com tiara de telemarketing, livro aberto.
  Sem dependência nova. Medida anti-overflow: glifo 24/28 + padding 6/8 (altura fixa 58/68).
- **V0.1.146 — voz on-device em isolate + relatório de erros:** síntese sherpa sai da
  thread da UI (fim do ANR/travamento ao ouvir) + `Diagnostico` (buffer local, menu ⋮ →
  "Relatório de erros": enviar/compartilhar/limpar) + aquecimento mais cedo do Muse.
- **V0.1.147 — falante pausa/retoma + sem crash:** o botão do alto-falante na resposta
  agora PAUSA de verdade e RETOMA do mesmo ponto (player.pause/resume; trecho de fallback
  do TTS é re-falado). Segurar o botão PARA de vez. Causa do "Taskix parou": `speak`/`play`/
  `pause`/`resume`/`stop` sem try/catch (race no Android = exceção não-tratada) + toques
  duplos concorrentes — tudo blindado (`_trocandoVoz`, try/catch com `Diagnostico.registrar`)
  e pausa automática ao sair do app. Botão maior (18→26, área 4→10).
- **V0.1.148 — pronúncias hmm/clean/and:** `hmm`/`hm`→"hum" (só o som do "m", sem dizer
  "emi"), `clean`→"clin", `and`→"end" nos DOIS lados (`PRONUNCIA_FALA` no proxy +
  `_normalizarFala` no app). `\b` protege `WhatsApp`/`Android`.
- **V0.1.149 — barra reorganizada:** coluna à direita com ANEXO pequeno (32px, ícone 20)
  em cima + ENVIAR grande (FAB normal 56px, ícone 28) embaixo; caixa de texto com
  `minLines: 3` p/ acompanhar a altura total. Anexar desabilita gravando/enviando; X de
  cancelar segue à esquerda durante a gravação. (MUSE.md §6 atualizado.)
- **V0.1.150 — desenhos da prateleira maiores:** glifo 24/28→26/32 (máximo que cabe na
  altura fixa 58/68 sem overflow — validado nos testes de widget). Galeria `topo/` com
  30 sugestões p/ os botões de dentro do projeto (só visual, nada implementado).
- **V0.1.151 — fala de contagens + fim do X lateral:** (1) contagens hifenizadas de 1
  dígito ("4-7-8", "4-4") viram "4, 7, 8" na FALA (pausa curta, sem "menos") nos DOIS
  lados; restrito a 1 dígito p/ preservar datas, telefones e intervalos.
  (2) Removido o X à esquerda da caixa durante o ditado (estreitava a caixa): agora
  TOCAR na caixa para a gravação mantendo o texto (dica no hint); enviar segue
  concluindo e enviando.
- **V0.1.152 — botões nº 04 terracota no topo do projeto:** no tema Terracota, os 5
  botões da parte superior direita (Muse, Pastas/Abas, PDF, Copiar, Excluir) viram
  plaquinhas fundo escuro `#0C0C0D` + desenho terracota (ideia 04 da galeria
  `topo/`); demais temas seguem com IconButton padrão. `_BotaoTopo`/`_TopoPainter`
  (`CustomPainter`, geometria 96x96 dos SVGs; "PDF" via `TextPainter`). Sem
  dependência nova.
- **V0.1.153 — plaquinhas do topo mais largas:** `_BotaoTopo` 34→40px de largura
  (altura 34 mantida).
- **V0.1.154 — bege/enviar preto + topo unificado + prateleira maior:** (1) tema Bege:
  botão de enviar PRETO (fundo `#000`, ícone branco; gravando segue vermelho). (2) Os 5
  botões do topo do projeto (Muse, Pastas, PDF, Copiar, Excluir) usam a plaquinha em
  TODOS os temas (fundo escuro fixo + desenho na cor de acento do tema via `app.fab`;
  helper `_botaoTopo` removido). (3) Prateleira: glifo 26/32→30/36 SEM aumentar a caixa
  (padding 4/5→2/3, gap 3→2 — validado nos testes de widget).
- **V0.1.155 — ditado não apaga + banner com modelo + caixa WhatsApp:** (1) Pausa no
  ditado apagava tudo: parcial vazio de fim de sessão zerava a caixa e o restart
  comitava o vazio como base. Fix: parcial vazio ignorado + resultado nunca encolhe o
  texto + sem restart duplo (`_stt.isListening`). (2) Banner do chat agora mostra
  `Modo • Tamanho • Modelo` (ex.: "Modo Calis • Curto • Caprichado"), centralizado.
  (3) Caixa estilo WhatsApp: `maxLines` 5→10 com `Scrollbar` sempre visível (corta pelo
  topo, 10 linhas visíveis). (MUSE.md §6 atualizado.)
- **V0.1.156 — pronúncias schopenhauer/nietzsche/haha:** `schopenhauer`→"chopenrráuer",
  `nietzsche`→"níti", `haha`→"rá rá rá" nos DOIS lados (proxy + on-device; MUSE.md §4).
  Galeria `muse-topo/` com 36 sugestões p/ a barra do chat (só visual).
- **V0.1.157 — topo do chat Preenchido:** botões do topo (voltar, lupa, modo,
  conversas, menu ⋮) viram plaquinhas preenchidas na cor de acento do tema +
  desenho branco (ideia 02 da galeria). `_placaTopo` (toque) e `_placaTopoMenu`
  (menus modo/⋮ via `child:`, sem o IconButton de 48px que estouraria os 34px).
  Título segue texto (nome da conversa, dinâmico).
- **V0.1.158 — topo do chat igual ao de dentro do projeto:** plaquinhas deixam de ser
  preenchidas e viram fundo escuro `#0C0C0D` + borda `#2A2A2B` + desenho na cor de
  acento do tema (via `IconTheme`, sem cor fixa nos Icons) — mesmo estilo das de
  dentro do projeto.
- **V0.1.159 — ditado à prova de pausa + vigia anti-mic-morto:** lido o fonte do
  plugin (7.5.0): o Android impõe pausa de 1–3s e pode encerrar a sessão SEM status
  (mic morto com botão vermelho). Blindagem: (1) retry do `listen` em 1s se falhar;
  (2) vigia a cada 2s — 6s sem evento com gravação ativa = `cancel` + recomeço;
  (3) trilha de `Diagnostico` (só metadados: status, tamanhos, erros — sem o texto
  ditado) p/ investigar no aparelho via Relatório de erros. Medos/inseguranças nos
  treinos documentados em `pessoal.md` da Muse (só VPS, sem restart).
  Se o stream falhar ANTES de qualquer frase, cai no envio normal (`enviarNaConversa`, robusto). O
  toque manual no alto-falante continua em **clipe único liso**. `/chat` segue intacto (reserva).
- **V0.1.160 — ditado tolera pausa curta DE VERDADE + botões ghost:** (1) **VOZ (bug do usuário:
  pausa de 1–2s truncava a fala):** a v0.1.159 só recomeçava no status `done`, mas com
  `cancelOnError:false` o reconhecedor nativo MORRE numa pausa curta (no-match/speech-timeout) SEM
  emitir `done` → `_aoStatusStt` não recomeçava e a captação ficava numa **zona morta** até o vigia
  (6s). Fix em `chat_screen.dart`: `_aoErroStt` no caso transitório agora REABRE a escuta na hora
  (`_reabrirVoz`: cancela o estado preso que o `cancelOnError:false` deixa, guarda o parcial em
  `_textoBase`, re-`listen`; debounced por `_reabrindoVoz`); e o vigia caiu de **6s→3s** (backstop).
  Pausar p/ respirar não corta mais. (2) **BOTÕES GHOST (escolha do usuário na galeria-Artifact,
  tema Terracota):** topo da **Muse** deixa de ser plaquinha preenchida (reverte 157/158) → GHOST na
  cor de **ACENTO** do tema (terracota no Terracota; branco é só home/projeto) via
  `_placaTopo`/`_placaTopoMenu` sem caixa/borda; **seletor de MODO = só a seta** (▾, o modo aparece
  marcado dentro do menu). Topo do **PROJETO**: `_BotaoTopo` ganha `destaque` — **Muse = chip de
  acento** (ação principal; glifo em `fabIcone`), os outros ghost na cor de texto (`textoUI`). Home
  inalterado (já era ghost). Analyze/dart não rodam na VPS → checagem manual + build no CI.
- **V0.1.161 — voz on-device (estilo Gboard) + botões maiores + voltar terracota + recomeçar fala:**
  (1) **VOZ:** relato "no Gboard consigo pausar e continua captando". O Gboard usa reconhecimento
  **ON-DEVICE contínuo** (não encerra a cada silêncio curto); ativado `SpeechListenOptions.onDevice`
  (`_onDevice=true`) no `_ouvirUmaVez`. **Fallback seguro:** se o aparelho não tem o modelo pt_BR
  offline (erro permanente) ou só dá erro sem captar nada (4×, contador `_errosOnDeviceSemTexto` que
  ZERA a cada texto captado → não rebaixa um on-device que funciona), desliga o on-device e segue na
  REDE sem interromper. (2) **BOTÕES MAIORES:** projeto `_BotaoTopo` 40×34/glifo22 → 44×40/glifo26;
  Muse `_placaTopo`/`_placaTopoMenu` 34×34/ícone20 → 40×40/ícone24 (seta do modo 22→26). (3)
  **VOLTAR da Muse** agora é `_placaTopo` (ghost na cor de ACENTO/terracota) em vez do back branco
  padrão — mesmo botão fecha a busca no modo busca. (4) **RECOMEÇAR A FALA:** na bolha da Muse, à
  ESQUERDA do alto-falante, botão `Icons.replay` (`_recomecarFala`) que toca a mensagem do INÍCIO
  mesmo se já tocando/pausada; o alto-falante segue tocar/pausar (segurar = parar).
- **V0.1.162 — reverte on-device + pronúncias (Schopenhauer no início / fati / nietzschiano):**
  (1) **VOZ:** o `onDevice` da v0.1.161 PIOROU no aparelho do usuário (cortava até ao respirar) →
  **revertido** (volta ao reconhecedor em rede da v0.1.160, que era o melhor estado do recognizer do
  app). Conclusão: o reconhecedor nativo one-shot do `speech_to_text` NÃO alcança o ditado contínuo do
  Gboard (motor SODA). Para pausas bem longas, o caminho é o **mic do próprio Gboard** na caixa de
  texto (tocar na caixa → mic do teclado). (2) **PRONÚNCIA — "Schopenhauer" na 1ª palavra saía errada
  (r fraco) e no meio certa:** causa = quando a síntese do 1º trecho vinha vazia (Piper frio), o
  fallback do **flutter_tts** falava `_vozTextos[i]` **CRU, sem `_normalizarFala`** (chat_screen.dart
  `_vozPlay`). Fix: normalizar também nesse fallback. Diagnóstico feito rodando o **espeak-ng** da VPS
  (`-x`): "Schopenhauer" cru → `sS,upyn^aU'er` (fraco) vs "chopenrráuer" → `...R'...` (R forte). (3)
  **Novas pronúncias** nos DOIS dicionários (cliente `_normalizarFala` + servidor `PRONUNCIA_FALA` em
  `/opt/taskix-chat/app.py`, serviço `taskix-chat` reiniciado): `fati→fáti`,   `nietzschiano→nitiano`,
  `nietzscheano→nitiano` (verificado no espeak: `fáti`=`f'ati`, `nitiano`=`n,iti'&~nU`).
- **V0.1.163 — voz configurável + versão gerada:** (1) **Voz na UI:** `VozController`
  (`lib/voz_config.dart`, `voz_velocidade_v1` 0.85–1.25 + `voz_id_v1` dii/faber) com seção
  "Voz da Muse" nas Configurações (slider de ritmo + Feminina/Masculina) e **"Fala devagar"
  por conversa** (menu ⋮, `Conversa.falaDevagar`, soma +0.16 ao lengthScale). On-device aceita
  velocidade por pedido (o isolate recria o motor sem derrubar a fila); faber pula o on-device
  e o `/tts` usa o modelo faber + `--length_scale` (faixa 0.7–1.4); fallback `flutter_tts`
  acompanha o ritmo. (2) **Versão gerada:** `lib/versao.dart` sai do `version:` do pubspec
  (`dart tool/gerar_versao.dart`, CI gera a cada build) + `test/versao_test.dart` trava —
  fim do dessync (V0.1.159 vs 0.1.162). (3) **Ações por voz no chat:** bloco
  `[[ACAO:lembrete|nota...]]` (proxy `_ACAO`, coach/geral/projetos) + `lib/chat/chat_actions.dart`
  (parse/execução/limpeza, máx. 2 por resposta, sem executar parcial) interceptado no reply
  final (`_rodar`/`enviar`, SnackBar de confirmação); `test/chat_actions_test.dart`.
- **V0.1.164 — versão em Configurações + guardrail de versão (nenhuma IA se perde):** (1) **Número da
  versão em Configurações:** `appVersao` na MESMA linha do título "Configurações", em fonte menor
  (12px) e cor suave (`projetos_screen.dart`, sheet de config). (2) **Guardrail anti-dessync:**
  `test/versao_test.dart` ganhou um 3º teste que amarra o `pubspec` à **entrada mais nova** do
  changelog (`- **V0.1.N` em §6) — antes só comparava `versao.dart`↔`pubspec` e deixou passar o furo
  da V0.1.163 (commits/changelog em 163, pubspec parado em 162). Agora bumpar sem a entrada do
  changelog (ou vice-versa) **falha o CI**. §12 reescrito: versão nos TRÊS lugares com o mesmo N.
  (3) Corrigido o dessync da V0.1.163 (pubspec 0.1.162→0.1.163).
- **V0.1.165 — atalho "ditar no teclado" (pausas longas):** botão de teclado
  (`Icons.keyboard_outlined`) na coluna do compositor da Muse, acima do anexar
  (`chat_screen.dart`). Chama `_ditarNoTeclado()`: foca a caixa + abre o teclado
  (`SystemChannels.textInput 'TextInput.show'`) p/ o usuário usar o **MIC do próprio
  teclado** (Gboard) — reconhecimento contínuo que aguenta pausas longas, ao
  contrário do segurar-enviar (recognizer one-shot do app, que corta em pausa
  curta — ver [[feedback_taskix_ditado_pausa_zona_morta]]). Na 1ª vez por sessão,
  `_snack` aponta onde fica o mic. Só UI; não mexe no recognizer do app.
- **V0.1.166 — "Tentar de novo" + "Editar e reenviar" no chat + reverte o ícone de teclado:**
  (1) **Reverte o ícone de teclado da V0.1.165** (redundante — tocar na caixa já abre o teclado;
  pedido do usuário). (2) **Tentar de novo / Editar** no `_acoesMensagem` (long-press na bolha, agora
  recebe `(ChatMessage, idx)`): **Tentar de novo** só na ÚLTIMA mensagem se for resposta da Muse
  (`_regenerar`: remove a resposta antiga, reenvia o MESMO histórico via `_escutarStream` → resposta
  nova, que varia pela persona "VARIE DE VERDADE" + temperatura); **Editar e reenviar** só na sua
  última mensagem (`_editarMensagem`: devolve o texto p/ a caixa sem os carimbos de anexo/imagem,
  remove a msg + o que veio depois; ao enviar, a Muse responde à versão corrigida). Ambos bloqueados
  durante um envio. Limitação: regenerar/editar um turno que tinha imagem perde a imagem (só o texto).
- **V0.1.167 — copiar não abre mais o teclado + doc do experimento GPT-5.6 Luna:** (1) **Bug:** ao
  Copiar uma mensagem (menu de ações), o teclado reabria sozinho — o bottom sheet, ao fechar,
  devolvia o foco à caixa. Fix: `FocusScope.of(context).unfocus()` no início de `_acoesMensagem`
  (o "Editar" refoca de propósito depois). (2) **Doc (sem código):** `MUSE.md §8` ganhou o
  experimento do **gpt-5.6-luna** — como o muse-spark, só fala a **Responses API** (`chat/completions`
  → 400 ModelProtocolUnsupported → fallback DeepSeek); custo ($0,20/$1,20, até + barato que o flash);
  comparação Muse (DeepSeek igual/melhor p/ coach; Luna + enxuto). Ver [[reference_opencode_zen_responses_api]].
- **V0.1.168 — LEMBRETES RECORRENTES (diário/semanal):** a Muse agora pode criar lembrete que
  REPETE. **App (`lembretes.dart`):** `Lembrete` ganhou `recorrencia` ('none'|'diario'|'semanal')
  + `repetindo`/`rotuloRecorrencia` (JSON compatível com antigos); `agendar(texto, daqui,
  {recorrencia})` usa `matchDateTimeComponents` (`.time` diário / `.dayOfWeekAndTime` semanal — mesmo
  mecanismo do backup semanal); `pendentes` mantém os recorrentes (âncora no passado, mas ativos); a
  lista "AGENDADOS" mostra "🔁 todo dia 08:00". **Ação (`chat_actions.dart`):** parse de `repete`
  (diario/semanal) e recorrência pro serviço via closure (typedef `AgendarLembrete` intacto → testes
  não quebram); confirmação "⏰ … (repete todo dia 08:00)". **Proxy (`app.py`, reiniciado):** `_ACAO`
  ensina `| repete=diario|semanal` + "você PODE criar recorrente agora". `flutter analyze` limpo (só
  o warning pré-existente de `projetos_screen.dart:806`).
- **V0.1.169 — botão de ENVIAR em degradê (ideia "C" do usuário, galeria de mockups):** o
  `FloatingActionButton` do compositor da Muse virou um botão redondo em **degradê** derivado do
  acento do tema (`Color.lerp(app.fab, white/black)` → claro→escuro; `fabIcone` no ícone), via
  `Material`+`Ink`+`InkWell` (gravando = vermelho sólido). Tirou o especial-case do tema Bege (o
  degradê sai do `fab` de cada tema). Mantido: caixa de texto sempre visível, anexo (+, imagens via
  ImagePicker) e o segurar-pra-ditar. `flutter analyze` do arquivo: No issues.
- **V0.1.181 — ajustes do chat (fonte, barra, botão por modo, sugestões):** (1) **Status no topo:** fonte 13→14; "fala devagar" não escreve mais "Devagar" — vira só o **ícone de velocidade** ao lado (dentro do contorno). (2) **Atalho da Muse dentro do projeto** agora volta ao shell e abre a **ABA Muse** (com a barra inferior), em vez de empilhar a lista sem a barra — pontezinha `nav_bus.dart` (`abrirAbaMuse`) registrada pelo `HomeShell`. (3) **Barra inferior:** o rosto da Muse ficou **maior (32) e mais nítido** (`FilterQuality.high`; pílula 36px). (4) **Botão de enviar por MODO:** mostra o dot do modo atual (Calis/Geral/Projetos) em vez do rosto geral (`_modoAsset`); gravando=vermelho+mic, enviando=ampulheta. (5) **Respostas de 1 toque:** `_SUGESTOES` ganhou um EXEMPLO (few-shot) + um lembrete de RECÊNCIA no fim do bloco volátil do `app.py` (relógio) p/ o modelo emitir o bloco de forma mais consistente (a pipeline cliente/servidor estava correta; era adesão do modelo). `dart analyze lib`: sem erros novos.
  - **Fallback determinístico das sugestões (servidor, sem APK novo):** reforçar o prompt NÃO bastou — o modelo emite o bloco nas 1ªs mensagens e esquece depois. Agora, no `app.py` (`/chat` e `/chat_stream`), se a resposta TERMINA com pergunta e NÃO trouxe `[[SUGESTOES:...]]`, o servidor **gera as 2 opções numa chamada curta e dedicada** (`_gerar_sugestoes`/`_com_sugestoes`; prompt focado só nisso, que o modelo obedece 100%) e anexa o bloco. Como é só servidor, **vale no APK já instalado** (o app só lê o bloco). Testado: "Quer que eu monte um plano?"→"Sim, por favor | Agora não".
- **V0.1.180 — dot por MODO antes de cada conversa:** cada conversa na lista
  (`ConversasScreen`) ganhou um dot/avatar do seu MODO — **Calis** (personagem
  verde na barra fixa), **Geral** (azul com fones + balão) e **Projetos** (roxo
  de óculos com laptop `</>`) — arte do usuário em `assets/muse/modo_<calis|geral|
  projetos>.png` (recortados em círculo, 256px). Diferente do rosto geral da Muse
  (por tema): aqui a cor é do MODO (verde/azul/roxo), para identificar o modo de
  cada conversa num relance. `leading` da `ListTile` via `_modoAsset(conv.preset)`.
- **V0.1.179 — ajustes finos do chat (Muse no lugar certo):** (1) **Lista de conversas:** removida a foto da Muse ao lado de cada conversa (fica só no cabeçalho "Muse Spark"). (2) **Atalho da Muse dentro do projeto** abre a LISTA de conversas (`ConversasScreen`), não a última conversa — a única forma de cair direto na última é o App Shortcut (segurar o ícone do app). (3) **Botão de enviar = o ROSTO da Muse** (a mascote vira o botão; gravando = vermelho+mic, enviando = ampulheta). (4) **Status no topo:** tirada a foto ao lado; a frase inteira cabe (`FittedBox`) e ganhou um **CONTORNO na cor do tema** (border em `app.fab`) em volta de "Modo • Tamanho • Modelo". (5) **Modelo e Tamanho ESCONDIDOS no menu ☰:** viraram 1 item cada ("Modelo: X" / "Tamanho: Y") que abre um seletor (bottom sheet) sob toque, em vez de ficarem expandidos. `dart analyze lib`: sem erros novos.
- **V0.1.178 — rosto da Muse = a mascote (imagem) + anel neon por tema:** o `MuseBlob` deixou de ser o blob geométrico (CustomPainter) e passou a mostrar a **arte do usuário** — a personagem rosa de óculos com o tablet (`file_…png` na raiz) — como identidade da Muse na barra inferior, na lista de conversas, no título do chat e no atalho dentro do projeto. **Diferenciação por tema (ideia do usuário):** a IDENTIDADE (personagem rosa) é constante; o que muda é o **ANEL neon** (contorno), recolorido no acento de cada tema. Pipeline (fora do app): o anel azul embutido foi recolorido por HSV **só na banda do raio do anel** (preserva o glow premium; cinza dessaturado no Dark Game) e recortado em CÍRCULO (cantos transparentes → funciona no tema Claro), gerando 7 PNGs 256px em `assets/muse/muse_<tema>.png` (~110 KB cada). `MuseBlob` (`lib/muse_blob.dart`) virou `Image.asset` escolhendo o arquivo pelo `AppCores` atual, com `errorBuilder` de reserva (círculo no acento). Removidos os params `cor`/`halo` (asset é por tema). `dart analyze lib`: sem erros novos.
- **V0.1.177 — topo do chat: status no título + nome da conversa no menu:** o banner "Modo • Tamanho • Modelo" (com o rosto da Muse) subiu para o **TÍTULO da AppBar** (no lugar do antigo nome da conversa) — o corpo da conversa começa direto, sem banner, ganhando espaço no topo. O **NOME da conversa** virou o **cabeçalho do menu ☰** (1º item, desabilitado), seguido de "Buscar na conversa", "Nova conversa", etc. `chat_screen.dart` (`build`/`_conversa`). `dart analyze lib`: sem erros novos.
- **V0.1.176 — 🐛 CORRIDA no carregar() (perda de texto) + ajustes de UX:** (1) **⚠️ BUG GRAVE corrigido — perda de texto ao trocar de tema/uso:** `Storage.carregar()` não deduplicava chamadas CONCORRENTES. Desde a V0.1.173 a aba **Estudos** (`_EstudosTab`) chama `carregar()` no startup JUNTO com a `ProjetosScreen` — as duas rodavam o corpo em paralelo e criavam **listas internas SEPARADAS**; uma tela editava a lista A enquanto `salvar()` gravava a lista B → o texto digitado sumia (sintoma do usuário: trocou Terracota→Ônix e uma caixinha ficou vazia). Fix: `carregar()` agora compartilha um **future em voo** (`_carregamentoEmVoo`) — uma única leitura, uma única lista (invariante "mesma referência"). Teste de regressão em `backup_test.dart` (carga concorrente devolve a MESMA lista + edição persiste). (2) **Teclado não reabre sozinho** ao fechar o menu ☰/M tocando fora: `PopupMenuButton.onOpened` tira o foco da caixa (`FocusScope.unfocus`). (3) **Botão M (modo) com área de toque cheia:** o `PopupMenuButton` só capturava o tamanho do filho (a letrinha) — agora a área toda (48×48) é tocável; `_placaTopoMenu` largura 40→48. (4) **Mensagens da Muse mais largas** (maxWidth 0.82→0.9). (5) **Pílula de status** já subira na V0.1.175. (6) **Versão removida do topo** da home (ao lado de "Taskix") — já aparece em Configurações. `dart analyze lib`: sem erros novos; testes de proteção de dados + corrida verdes.
- **V0.1.175 — ajustes do chat (pílula, sugestões, scrollbar) + blob no projeto:** (1) **Pílula de status mais no topo:** padding acima reduzido (8→2) + topo da lista 12→6 — menos espaço em branco no topo do chat. (2) **Respostas de 1 toque = no máximo 2** (`QuickReplies.maxOpcoes` 3→2) e prompt do servidor (`_SUGESTOES` no `app.py`, reiniciado) reforçado p/ a Muse emitir o bloco em TODO turno que fecha com pergunta (regra permanente, "exatamente 2"), não só na 1ª resposta. (3) **Scrollbar contido:** a lista de mensagens virou `Scrollbar(controller: _scroll, child: ListView)` (a barra fica DENTRO da área de conversa); removida a `Scrollbar(thumbVisibility: true)` do compositor, que ficava sempre visível e "vazava" flutuando sobre o fundo (a caixa ainda rola internamente até 10 linhas). (4) **Muse dentro do projeto = blob:** o botão da Muse na AppBar do `ProjetoScreen` (ao lado do título/"ver como pastas") virou o ROSTO da Muse (`MuseBlob`, tingido no acento), no lugar do glifo antigo (`_BotaoTopo` perdeu o modo `destaque`, sem uso). `dart analyze lib`: sem erros novos; testes QuickReplies ajustados (máx. 2).
- **V0.1.174 — tema "Claro":** novo 7º tema (`Modo.luz`, rótulo **Claro**) com o visual dos mockups de redesenho que o usuário aprovou — fundo cinza-claro FRIO (#EEF1F6→#E6EBF2), cartões/caixinhas BRANCOS flutuando com sombra suave, texto quase-preto (#121418), acento AZUL (#2E6BFF), fonte sem serifa padrão do sistema (mesma linguagem da barra flutuante e da Muse). `AppCores.luz` (`cores.dart`) + `_temaLuz()` (`main.dart`, reusa `_temaClaroCalis`, roda em `ThemeMode.light`) + card BRANCO com sombra no home (`ehLuz` em `projetos_screen.dart`). ⚠️ O `name` do enum é **`luz`**, NÃO `claro` — `claro` é nome legado migrado p/ `azul` na carga; reaproveitá-lo faria o tema cair na migração. Os demais 6 temas seguem com suas cores (o `MuseBlob` já tinge no acento de cada um). Testes: `tema_test.dart` (7 temas; cada um constrói sem erro). `dart analyze lib`: sem erros novos.
- **V0.1.173 — barra flutuante + Muse minimalista + blob por tema + respostas de 1 toque:** redesenho na linguagem "flutuante". (1) **Shell de navegação** (`lib/home_shell.dart`, `HomeShell`): barra inferior FLUTUANTE (contorno próprio, descola do fundo) com 3 destinos — **Projetos** · **Muse** (centro) · **Estudos** — num `IndexedStack`; abrir um projeto/conversa empilha rota cheia (a barra some, foco na tela) e o voltar traz a barra. `main.dart` passa a abrir no `HomeShell`. **Removida a prateleira** de acessos rápidos (`_AcessosRapidos`) e a função **Recentes** (inútil na prática) de `projetos_screen.dart` (`_recarregarRecentes` virou no-op; glifos da prateleira removidos). (2) **Aba Muse = LISTA primeiro** (`lib/chat/conversas_screen.dart`, `ConversasScreen`): tocar em "Muse" abre a lista de conversas; tocar numa conversa abre o chat; o **voltar ← do chat retorna à lista** (antes não existia). `ChatScreen` ganhou `conversaId`/`iniciarNova` (a lista escolhe a conversa; sem eles cai no legado "última conversa" do atalho do launcher). (3) **Topo do chat minimalista:** só **← (voltar p/ lista)**, **☰** (TUDO num botão: buscar, nova, resumo, renomear, relatório, modelo, tamanho, fala) e **M** (modo Calis/Projetos/Geral — mostra a inicial do modo atual, tingida no acento; toca e troca). A antiga folha "Conversas" (`_abrirHistorico`) e os botões soltos de busca/histórico/modo saíram. O banner virou uma **pílula flutuante** central com o rosto da Muse + "Modo • Tamanho • Modelo". (4) **Blob por tema** (`lib/muse_blob.dart`, `MuseBlob` — `CustomPainter`, FORA de `lib/chat/` p/ a barra usar sem puxar o chat): o rosto da Muse (esfera vítrea + "fones" + olhos) assume a cor de acento de CADA tema (`AppCores.fab`), como os glifos; sem asset novo. Usado na barra, na lista e na pílula. (5) **Respostas de 1 toque:** quando a Muse fecha com pergunta, o proxy emite `[[SUGESTOES: a | b | c]]` no fim (bloco estático no `app.py`, `_SUGESTOES`; só não-resumo); o app mostra como chips acima da caixa (`QuickReplies.extrair` em `chat_actions.dart`; stripping no `_semCarimbo`, pega bloco parcial no stream). Latência desprezível (vem no fim do streaming, sem chamada extra). (6) **`ProjetoScreen` ganhou `embutido`/`onVoltarNaRaiz`**: a aba Estudos embute o projeto reservado "Estudos" (modo pastas) com segurança — nunca sai da rota (voltar na pasta→grade; na grade→troca p/ aba Projetos), "Excluir" some, e os FABs ficam `heroTag: null` (evita colisão de Hero com um ProjetoScreen empilhado). Testes: `chat_actions_test.dart` (QuickReplies). `dart analyze lib`: sem erros (warnings/infos pré-existentes).
- **V0.1.172 — "Feito" na notificação + alarmes que abrem a Muse perguntando + resumo semanal:** (1) **Botão "Feito ✓"** na notificação do lembrete (cancela e tira dos pendentes sem abrir o app; o 3º botão vira ele no lugar do "+24 h" — o backup semanal mantém os 3 snoozes e não tem Feito, p/ nunca matar a série; série recorrente nunca é cancelada pelo Feito). (2) **Alarmes inteligentes**: bloco de lembrete aceita `| abrir=coach|projetos|geral | dizer=<pergunta>` (proxy ensinado no `_ACAO`); tocar no corpo abre a Muse naquele modo e **envia a pergunta sozinha** (conversa nova; roteamento via pedido em prefs+notify, snooze preserva o payload). (3) **Resumo semanal** (servidor, sem APK): `resumo_semanal.py` (1x/semana, domingo 06–22h, estado por semana ISO) injeta o fechamento da semana (treinos, joelho se mencionado, leitura, foco seguinte) quando conecta com o assunto. Testes: `lembretes_muse_test.dart` (payload/Feito) + 3 de abrir/dizer no `chat_actions_test.dart` + `tests_resumo_semanal.py`.
- **V0.1.171 — caixa da Muse não joga p/ o fim ao tocar/editar no meio:** `onTap` e
  `onChanged` do TextField chamavam `_rolarCaixaFim()` incondicionalmente — tocar num
  trecho no meio de mensagem longa (ou digitar nele) rolava a caixa até a última linha
  e escondia o trecho. Agora o fim só é acompanhado quando o cursor está no fim
  (`extentOffset >= text.length`, que é o caso do ditado e da digitação normal);
  editar no meio deixa o scroll onde está (o próprio campo revela o cursor).
  Regra registrada no comentário do `_rolarCaixaFim`.
- **V0.1.170 — voltar dentro de pasta retorna à grade:** projeto aberto "em modo pastas"
  (ex.: Estudos) ganhava `PopScope` na `ProjetoScreen`: o 1º voltar do sistema, estando
  dentro de uma pasta, volta À GRADE de pastas — só o 2º voltar sai para a lista
  (`canPop: _modoPastas || !modoPastasInicial || _saindo`; `_saindo` libera o pop real
  da exclusão do projeto, senão o veto o seguraria). Sem `modoPastasInicial`, o voltar
  sai direto como antes. Teste em `test/voltar_pastas_test.dart` (2 testes).
- **Tempo em Lajeado/RS (servidor, sem APK novo):** novo `tempo.py` no proxy
  (Open-Meteo, sem chave): atual+máx do dia+chuva por turno (manhã/tarde/noite).
  Entra sob pergunta explícita (qualquer hora, com guarda anti-"tempo"=duração)
  ou automático na 2ª msg da manhã (05–12h, 1x/dia). Cache 90 min + estado em
  `/var/lib/taskix-chat/tempo.json`. Testes em `tests_tempo.py`.
- **Placar do tempo (servidor, sem APK novo):** `tempo.py` salva o palpite do
  dia dos 3 modelos (ECMWF/GFS/ICON) e apura o anterior (temp: menor erro na
  máxima; chuva: mais turnos certos, >0,2 mm) contra o best_match. Placar
  semanal vai às segundas e sob "qual modelo acertou mais?"; a Muse sempre
  cita a fonte (Open-Meteo).
- **Armazenamento:** a conversa atual é local (`chat_store.dart`, chave `taskix_chat_v1`) —
  **não** toca no `Storage` dos projetos nem na cadeia de proteção (REGRA DE OURO intacta).

---

## 7. CI/CD — Build do APK

**Trigger:** push na `main` (pastas `lib/`, `pubspec.yaml`, `android/`, `.github/workflows/`) + manual (`workflow_dispatch`).

**Fluxo:**
1. Checkout + Java 17 + Flutter 3.44.7
2. `flutter pub get`
3. Decodifica `secrets.KEYSTORE_BASE64` → `android/app/upload-keystore.jks`
4. Cria `android/key.properties` com senhas do `secrets.KEYSTORE_PASSWORD`
5. `flutter build apk --release`
6. Publica na release `v0.1.0`: sobe **`taskix-v<versao>.apk`** (nome VERSIONADO,
   à prova de cache — cada versão é um download distinto) + o `app-release.apk`
   fixo (compat.), e ajusta título/notas da release para a versão atual. ⚠️
   Motivo (V0.1.62): reinstalar do mesmo nome `app-release.apk` servia APK em
   CACHE → usuário reinstalava versão velha achando que atualizou. Sempre
   orientar a baixar o **`taskix-v<versao>.apk`** e conferir a versão no topo da
   tela inicial.

**Secrets necessários:** `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`

**Keystore local:** `android/app/upload-keystore.jks` + `android/key.properties` (não commitados — `.gitignore` ignora `*.jks` e `key.properties`).

---

## 8. Comandos Úteis (sempre na pasta `/root/adm-projetos`)

```bash
# Análise estática
flutter analyze

# Testes (161 testes)
flutter test

# Build local (não usado — build é feito no GitHub Actions)
flutter build apk --release

# Commit + push (usar este padrão)
cd /root/adm-projetos && git add -A && \
  git -c user.name="Vinícios Tristao" -c user.email="viniciostristao@gmail.com" \
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
3. Definir valor nas 7 constantes (`azul`, `escuro`, `neumB`, `bege`, `claude`, `onix`, `luz`)
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
- **crypto:** `^3.0.6` — SHA-256 salgado da senha de projeto (V0.1.93; só hash,
  NÃO criptografa conteúdo). Ver `seguranca.dart`.
- **quick_actions:** `^1.1.0` — App Shortcut "Nova nota" (segurar o ícone do
  app). Configurado no `_ProjetosScreenState` (V0.1.93).
- **flutter_launcher_icons:** `^0.14.4` — gerar ícones do app (dev only)
- Não há pacote `http` — requisições HTTP usam `dart:io` `HttpClient` diretamente.

---

## 10. Testes (161 testes)

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
- **(V0.1.63)** esconder o teclado solta o foco IMEDIATAMENTE; e durante
  composição IME (meio de uma palavra) um "altura 0" passageiro NÃO solta o foco

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

### `test/lembrete_dia_semana_test.dart` (4 testes — V0.1.87/88)
- `quandoComDiaSemana`: exemplo do usuário ("22/09 • 09:00 • Terça-feira"), zero
  à esquerda em dia/mês/hora, os 7 dias por extenso (Segunda a Domingo),
  meia-noite e 23:59

### `test/minimizar_test.dart` (9 testes — V0.1.86/89)
- Serialização de `Nota.minimizada`: round-trip preserva; JSON antigo sem o
  campo vira `false`; `toJson` omite quando false
- Widget real (`ProjetoScreen`): botão `•••` minimiza (campo some, prévia com
  `maxLines: 3` + `ellipsis`, estado salvo no modelo) e expande de novo
- **(V0.1.89)** minimizada OCULTA a barra de ferramentas e mostra os botões
  copiar + `•••` no fim do texto; copiar continua copiando o texto INTEIRO
  (mock do clipboard) e o `•••` da prévia expande (barra e campo voltam)
- **(V0.1.89)** a prévia corta as 3 primeiras linhas INTEIRAS sem "…" (o
  corte numa quebra "dura" de linha não come a 3ª linha)
- Minimizada mantém os títulos dos links visíveis e esconde o comentário
- Com busca ativa a caixinha minimizada aparece expandida (estado salvo intacto)

### `test/senha_test.dart` (8 testes — V0.1.93)
- `hashSenha`/`gerarSalt`: determinístico (mesmo salt+senha → mesmo hash),
  senha errada não confere, salts diferentes → hashes diferentes, nunca guarda
  a senha em texto puro (SHA-256 hex de 64 chars), salt aleatório.
- Serialização do `Projeto` com senha: round-trip preserva `senhaHash`/
  `senhaSalt` E o conteúdo (REGRA DE OURO — backup/restore não perde nada; a
  senha ainda confere depois); sem senha os campos são omitidos (`temSenha`
  false); JSON antigo sem os campos carrega como sem senha.

### `test/reorder_secoes_prioridade_test.dart` (8 testes — V0.1.94)
- Reorder com QUATRO seções por prioridade (FOCO / EM ANDAMENTO / PRÓXIMOS /
  OUTROS) contra o `ReorderableListView` real, foco=amarelo, próximos=verde.
  `secaoDe`: FOCO vence (cor foco + andamento = FOCO; andamento > próximos);
  `montarLinhas` na ordem certa; mover dentro de FOCO/EM ANDAMENTO; FOCO não
  vaza p/ baixo; PRÓXIMOS (seção do meio, limitada dos dois lados) não vaza p/
  cima (EM ANDAMENTO) nem p/ baixo (OUTROS); sem FOCO/EM ANDAMENTO, PRÓXIMOS é
  a 1ª seção. Réplica fiel de `_secaoDoProjeto` + `_linhasComSecoes` +
  `_reordenarComSecoes`.

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

### `test/versao_test.dart` (2 testes — V0.1.163)
- `versao.dart == version do pubspec` (trava o dessync; manda rodar o gerador)
- `versao.dart` avisa que é gerado

### `test/voz_config_test.dart` (3 testes — V0.1.163)
- Defaults (1.04×, dii) sem nada salvo
- Roundtrip + faixas/vozes inválidas caem no seguro
- `Conversa.falaDevagar`: default false, JSON antigo sem a chave compatível

### `test/chat_actions_test.dart` (11 testes — V0.1.163)
- Parse (válidos, case-insensitive, desconhecido/quebrado ignorados), limpeza
- Execução com fakes (sucesso, passado rejeitado, default Estudos, parcial não
  executa, máx. 2, gigante/vazio ignorados, falha vira aviso)

### `test/voltar_pastas_test.dart` (2 testes — V0.1.170)
- Projeto com `modoPastasInicial`: entrar na pasta, 1º voltar do sistema volta
  À GRADE (rota preservada), 2º voltar sai para a lista
- Sem `modoPastasInicial`: voltar sai direto (comportamento antigo intacto)

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
- **Sempre rodar `flutter test`** — 161 testes devem passar.
- **Nunca commitar `android/key.properties` ou `*.jks`** — já no `.gitignore`.
- **Assinatura do APK é fixa** — permite atualizar o app sem desinstalar.
- **VPS com pouca RAM — trabalho leve (incidente 2026-10-12: swap 100%, PSI alto após
  `flutter test` + venv de teste):** ~4 GB de RAM, sem build local de APK (o CI faz).
  1 comando pesado por vez; `pip install` de teste só em venv descartável em `/tmp`;
  após comandos pesados, conferir resíduos (`ps`); em alerta de pressão, ver `free -m` +
  maiores consumidores e só matar sessão ociosa **confirmada** (identificar a própria
  sessão pela cadeia de PPID antes; nunca matar às cegas).

---

## 12. Fluxo de Release (versão do app)

A cada publicação de APK:

1. **Versão em TRÊS lugares, com o MESMO número N** (fonte única = `pubspec.yaml`):
   1. **Bumpar** o `version:` do `pubspec.yaml` (`0.1.163+163` → `0.1.164+164`).
   2. **Regenerar** `lib/versao.dart` com `dart tool/gerar_versao.dart` (o CI
      também gera a cada build).
   3. **Adicionar** a entrada do changelog em §6, no formato EXATO
      `- **V0.1.N — <resumo>:** …` (o `N` tem de ser o mesmo do pubspec).
   ⚠️ **`test/versao_test.dart` ENFORCE os três:** `versao.dart`↔`pubspec` **e**
   `pubspec`↔**entrada mais nova** `- **V0.1.N` do AGENTS.md. Se você bumpar o
   pubspec e esquecer o changelog (ou vice-versa), o `flutter test` do CI
   **falha** — então nenhuma IA se perde no número (foi o furo da V0.1.163: commits
   em V0.1.163 com pubspec parado em 0.1.162; o teste antigo só via versao.dart↔pubspec e passava).
2. A versão aparece no topo da tela principal (ao lado de "ADM-projetos") —
   o usuário confirma que está rodando o APK certo.
3. **Informar o número da versão na resposta do chat** (ex.: "Versão publicada: **V0.1.23**").
4. **SEMPRE mandar o LINK DIRETO do APK na resposta do chat** (pedido do
   usuário — não esquecer ao terminar qualquer tarefa que gera build). O CI
   sobe DOIS assets na release fixa `v0.1.0`: `app-release.apk` (nome fixo) e
   `taskix-v0.1.<N>.apk` (versionado). Mandar o **versionado**:
   `https://github.com/viniciostristao1/adm-projetos/releases/download/v0.1.0/taskix-v0.1.<N>.apk`
   Só enviar depois que `gh run list --workflow=build-apk.yml` mostrar
   `completed success` e o asset existir (`gh release view v0.1.0 --json assets`).
5. **SEMPRE fazer commit e push imediatamente após bump de versão** — nunca
    deixar a versão só local. Padrão: `git add -A && git -c user.name="Vinícios Tristao" -c user.email="viniciostristao@gmail.com" commit -m "V0.1.<N>: <resumo>" && git push` e só então enviar o link do passo 4. ⚠️ Esquecer o push = o APK nunca é gerado e o usuário fica sem link (falha da V0.1.76).

## 13. Histórico de Decisões

| Decisão | Motivo |
|---|---|
| **Acessos rápidos: 3 caixinhas RECENTES / ASSISTENTE / ESTUDOS (V0.1.110)** | Pedido do usuário. Substituiu a prateleira rolante RECENTES por 3 caixinhas lado a lado, com título centralizado em cima (`_AcessosRapidos`). **RECENTES** abre DIRETO o último projeto (não mais uma prateleira de 5). **ASSISTENTE** abre a Muse — o antigo FAB de mensagem ao lado do "+" foi REMOVIDO. **ESTUDOS** abre o projeto reservado "Estudos" (cria se não existir) em MODO PASTAS (`modoPastasInicial`), onde o usuário cola trechos da Muse / resumos de vídeos (entra na busca global normal); a Muse ganhou "Salvar no Estudos" (segurar a bolha → menu) via `Storage.adicionarNotaEmProjeto`. A data do último envio à nuvem (antes na linha RECENTES) saiu da home. |
| **FOCO + PRÓXIMOS: seções por cor e prioridade (V0.1.94)** | Evolução do "EM ABERTO" (V0.1.92) a pedido do usuário. A home agora tem 4 seções por PRIORIDADE: **FOCO** (topo, projetos principais) → **EM ANDAMENTO** → **PRÓXIMOS** (renomeia "EM ABERTO") → **OUTROS**. FOCO e PRÓXIMOS são dirigidos pela COR da pasta, cada um com sua cor configurável em Configurações → "Foco e Próximos" (padrão foco=amarelo, próximos=verde; "nenhuma" desliga; migra a antiga `cor_em_aberto_v1` → próximos). Classificação única `_secaoDoProjeto` (0=FOCO/1=ANDAMENTO/2=PRÓXIMOS/3=OUTROS): **FOCO vence** (checado 1º, mesmo se o projeto também estiver "em andamento"). As duas cores não podem colidir — a cor de um grupo fica bloqueada no seletor do outro (e `definirCorFoco/Proximos` limpa a outra se coincidir). Reorder segue confinado por seção (reusa `_grupoDoProjeto`+`_reordenarComSecoes`, agora com a seção do meio PRÓXIMOS limitada dos dois lados). Cabeçalhos FOCO/PRÓXIMOS na própria cor; o seletor de cor da pasta (long-press) mostra "amarelo = Foco · verde = Próximos". Coberto por `test/reorder_secoes_prioridade_test.dart`. |
| **Senha de projeto + lembrete semanal de backup + atalho "Nova nota" (V0.1.93)** | Três pedidos do usuário. (1) **Senha de projeto:** no "Editar pasta" (long-press) há "Proteger com senha" / "Remover senha"; projeto trancado pede a senha ao abrir (`_liberarAbertura`), some do conteúdo da busca global (o nome ainda aparece; abrir pede senha) e mostra 🔒 no cartão. **Decisão-chave:** é TRANCA DE CONVENIÊNCIA — guarda só o SHA-256 salgado (`seguranca.dart`), NÃO criptografa o conteúdo. Motivo: a REGRA DE OURO é *nunca perder conteúdo* — criptografar + esquecer a senha = perda permanente; com hash, esquecer só impede abrir pela tela, o conteúdo segue no backup/export (recuperável). Remover a senha EXIGE a senha atual (senão long-press burlaria). (2) **Lembrete semanal de backup:** toggle + dia/hora nas Configurações → Backup; agenda uma notificação local RECORRENTE (`matchDateTimeComponents: dayOfWeekAndTime`, id fixo `900001`) só para LEMBRAR de salvar — NÃO faz backup sozinho (a nuvem segue 100% manual). (3) **Atalho "Nova nota":** `quick_actions` — segurar o ícone do app abre o projeto "Notas rápidas" (cria se não existir) já com uma caixinha nova focada (`ProjetoScreen.adicionarAoAbrir`). |
| **Seção "EM ABERTO" por cor + arrastar caixinha p/ excluir (V0.1.92)** | Pedido do usuário. (1) **EM ABERTO:** nas Configurações escolhe-se uma cor de pasta; na tela inicial os projetos (não em andamento) nessa cor viram a seção "EM ABERTO · N" (contagem = projetos naquela cor), entre "EM ANDAMENTO" e "OUTROS". Cor guardada em `TemaController.corEmAberto` (SharedPreferences `cor_em_aberto_v1`); null = recurso desligado. Para não duplicar lógica (histórico de bugs de reorder com seções — V0.1.68/69/70), a montagem das seções e a classificação viraram helpers ÚNICOS `_linhasComSecoes` + `_grupoDoProjeto`, usados tanto na exibição quanto no `_reordenarComSecoes` (generalizado p/ 3 grupos; o `ini` recua até a borda e o `dest` faz clamp, então cada seção fica contida mesmo sendo a do MEIO, limitada por cabeçalho dos dois lados). Cabeçalho EM ABERTO pintado com a cor escolhida. Coberto por `test/reorder_tres_secoes_test.dart`. (2) **Arrastar caixinha p/ a esquerda = excluir** (com Desfazer, reusa `_excluir`): mesmo padrão dos cartões de projeto na home — `Dismissible` (`endToStart`) como widget de topo do item (carrega a key do reorderable); o reorder segue vindo do pino interno (`ReorderableDragStartListener`), então os dois gestos coexistem (padrão já provado na home). |
| **Fix do logo: sombreado atrás das molas (V0.1.91)** | O usuário notou uma névoa/brilho do neon subindo por trás dos "arames"/molas do topo (acima da borda do quadro), sobre o preto. Limpei essa faixa superior (`assets/icono.png` via PIL: acima de `y≈0.15h`, pixels de fundo com brilho `<56` → preto, com **transição suave** perto da borda do quadro p/ não criar emenda dura; molas e quadro intactos). Regenerei `icono_titulo.png` (trim) e os ícones do launcher. Validado por antes/depois. |
| **Novo logo Taskix (V0.1.90)** | Usuário enviou uma arte nova (TX neon em bloco de notas). Substituiu `assets/icono.png` (fonte do ícone do app — `flutter_launcher_icons` regenerado, mipmaps commitados pois o CI não roda o gerador) e criou `assets/icono_titulo.png` (badge recortado, sem a margem preta) para o logo ao lado do título "Taskix" (AppBar 24px + empty-state 56px, `projetos_screen.dart`). |
| **"+" rola até a caixinha nova (V0.1.90)** | Com muitas caixinhas, a nova nascia fora da viewport; como a `ReorderableListView` é LAZY, o item nem era construído → o `focarNoFim()` no post-frame achava `currentState==null` (nem focava nem rolava). Fix: `ScrollController` POR ABA (`_scrollAbas`, o TabBarView tem uma lista por aba → controller único daria conflito) + `_revelarNota` rola até `maxScrollExtent` em passos (a lista lazy cresce o extent a cada rolagem) e só então foca. |
| JSON local em vez de Firebase | Simplicidade, offline-first, sem custo |
| 7 temas (Azul/Escuro/Dark Game/Bege/Terracota/Ônix/Claro) | Preferência do usuário; Bege e Claro são claros, os demais escuros |
| Tema Claude Code (terminal) com JetBrains Mono | Escolha do usuário: preto-quente + terracota + fonte mono, cartões como linhas de 1px |
| Prateleira "Recentes" (5 projetos) na página principal | Ideia do usuário (prateleira rolante) aplicada aos projetos mais recentes |
| Seções "EM ANDAMENTO"/"OUTROS" na lista de projetos | Ideia do usuário: o marcador de em andamento vira agrupamento; arrastar só dentro da seção |
| **Arrastar pasta PARA BAIXO consertado (V0.1.68)** | `onReorderItem` (Flutter 3.44.7) já entrega `newIndex` ajustado; o antigo `if (newIndex > oldIndex) newIndex--` ajustava de novo → todo move para baixo caía em `newIndex == oldIndex` e virava no-op (só subir funcionava). Removido o ajuste em `_reordenarComSecoes`. Não toca em Storage/dados. |
| **Reorder na seção EM ANDAMENTO consertado (V0.1.69)** | Cartão (60px) mais alto que o cabeçalho da próxima seção (30px): ao soltar no fim da seção, o SDK devolve o índice do CABEÇALHO seguinte → o `if (newIndex > fim) return` rejeitava e a pasta voltava. Travava TODO reorder da seção EM ANDAMENTO (seguida por cabeçalho); OUTROS (última, sem cabeçalho) funcionava. Fix: removido o early-return, o `dest.clamp` mantém a pasta na própria seção. Validado com arraste real: `test/reorder_secoes_test.dart` (7 testes). |
| **CAUSA RAIZ do reorder com seções (V0.1.70)** | `_reordenarComSecoes` fazia `_projetos = [..]` (reatribuía p/ lista nova), quebrando o vínculo com a lista INTERNA do Storage (`_projetos` é a mesma referência que `carregar()` devolve). Resultado: `salvar()` gravava a ordem antiga e o `notifyListeners()`→`_aoMudarStorage` revertia a tela → com um projeto EM ANDAMENTO, as pastas de OUTROS "não saíam do lugar". Fix: mutar no lugar (`_projetos..clear()..addAll(...)`), como o `_reordenar` plano já fazia. Regra: reorder/edição nunca reatribui `_projetos`. Teste do widget REAL: `test/reorder_real_screen_test.dart`. |
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
| **APK versionado na release (V0.1.62)** | Erro "Generic IDP" persistia mesmo após a V0.1.61 porque o usuário reinstalava um APK em CACHE (mesmo nome `app-release.apk`). CI passou a publicar `taskix-v<versao>.apk` (nome distinto por versão) — download sempre fresco |
| **Teclado `unfocus` imediato (V0.1.63)** | O debounce da V0.1.57 fazia o teclado "voltar a subir" (minimizar 2-3× com o cursor no fim). Voltou a soltar o foco na hora, guardado por composição IME. Notificação: config já é max+som+public+exact; misses raros (1/10) e sem-som em testes rápidos = OEM/Doze/rate-limit, não código → orientar liberar bateria |
| **Teclado no desbloqueio facial — escada + `_retomando` (V0.1.83)** | Face unlock mandava `inactive` com o teclado ainda aberto → `_tinhaFocoAoParar` armava e, ao `resumed`, o `bottom >0→0` atrasado caía já `resumed` e o `unfocus` imediato derrubava o teclado no meio do `TextInput.show` (flicker "subiu e baixou"). Fix: janela `_retomando` que suprime o `unfocus` durante a escada 220/520/900; a escada só mostra o teclado se `bottom == 0` e usa `Timer` cancelável (evita reaberturas sobrepostas do keyguard). `unfocus`+`refocus` síncrono removido (era no-op de `FocusManager`). |
| **`ic_notif` no manifesto + "Outro" sem reticências (V0.1.67)** | Notificações quebraram (`invalid_icon`): o `ic_notif` da V0.1.65 era removido no build release (usado só por string em runtime) → referenciado no manifesto p/ manter no APK. E o chip "Outro" perdeu o ícone `more_horiz` (parecia "…Outro") e a linha dos tempos virou `Wrap` (cabe sem rolar) |
| **Caixinha limpa + cor da pasta (V0.1.76)** | Nova caixinha em Tarefas não inicia mais com `1- ` (limpa; numeração só ao tocar no botão). Pasta: segurar abre leque de 7 cores (azul/amarelo/vermelho/verde/roxo/marrom/bege) + sem cor; `Projeto.cor` guardada; em andamento sobrepõe com `fab` do tema e volta à cor ao desmarcar. Barra de 4px via `ClipRRect+Stack` (evita `borderRadius` em `Border` não-uniforme). |
| **Editar pasta por segurar — sem lápis na linha (V0.1.84)** | Segurar a pasta abre folha "Editar pasta" com campo de nome (TextField + botão ✓) + seletor de cor; o lápis `edit_outlined` saiu da linha da pasta (só restam arraste ⋮⋮ à esquerda e ✓ de andamento à direita). Folha com `isScrollControlled` + `viewInsets` para o teclado, cores aplicadas via `_definirCorPasta`. Cartão plano também virou `Material+InkWell` de card inteiro (antes só o texto tinha long-press). |
| **Folha "Editar pasta" fecha ao salvar (V0.1.85)** | Toque no V do nome (ou Enter) e toque numa cor fecham a folha (`Navigator.pop`) para dar feedback e mostrar a pasta atualizada. Antes a folha ficava aberta e parecia que nada tinha acontecido. |
| **Minimizar caixinha "•••" — 3 linhas (V0.1.86)** | Pedido do usuário: botão `more_horiz` minimiza a caixinha para as 3 primeiras linhas com reticências. Estado POR caixinha salvo no modelo (`Nota.minimizada`, JSON backward-compatible — escolha do usuário "lembrar sempre"); comentário esconde, títulos de links ficam. Busca ativa expande; ferramentas de edição expandem via `_garantirExpandida()`. |
| **Dia da semana no resumo do tempo montado (V0.1.87)** | Pedido do usuário: no modo "monte o tempo (vai somando)" o resumo agora mostra a data completa com o dia da semana abreviado (ex.: "22/09 • 09:00 • Ter.") via `quandoComDiaSemana` (nome PT fixo, sem dependência nova). A lista AGENDADOS e a notificação seguem com o formato antigo (`_quando`). |
| **Dia da semana por extenso (V0.1.88)** | O usuário viu no aparelho que as 3 infos não cabem lado a lado e pediu para NÃO abreviar: `quandoComDiaSemana` passou a devolver "Terça-feira" (etc.), quebrando para a 2ª linha quando preciso. Só mudou o rótulo do resumo do tempo montado. |
| **Minimizada com barra oculta + botões no fim (V0.1.89)** | Pedido do usuário: o "•••" agora ESCONDE a barra de ferramentas e o fim da 3ª linha ganha os botões **copiar** (`copy_all_outlined`) e **"•••"** (expandir), no lugar das reticências. O texto é medido/cortado numa fronteira de palavra (`_textoPrevia`) para os botões caberem sem "…"; busca ativa segue expandindo. Botões compactos `_BotaoPrevia`; barra extraída para `_barraFerramentas` e renderizada só quando expandida. Teste novo em `minimizar_test.dart`. |

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
- **Etiquetas/cores por projeto** + filtro rápido. (Parcial desde V0.1.92: a
  cor da pasta já agrupa nas seções FOCO/PRÓXIMOS; falta filtro/multietiqueta.)
- **"Limpar concluídas"** — apagar/arquivar de uma vez as caixinhas marcadas.
- **Compartilhar 1 projeto como texto** (hoje há PDF e "copiar tudo").
