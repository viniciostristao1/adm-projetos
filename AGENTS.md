# ADM-projetos — AGENTS.md (Referência Canônica)

> Documento de referência para IA e desenvolvedores.  
> Toda alteração no app deve manter este arquivo atualizado.

---

## 1. Visão Geral

App Android (Flutter) para **anotar ideias** em projetos, com listas numeradas, checkboxes, links, comentários, temas e backup.

- **Nome do app:** ADM-projetos
- **Pacote Android:** `com.admprojetos.adm_projetos`
- **Flutter:** 3.44.7 (stable) — `pubspec.yaml`: SDK `^3.12.2`
- **Repositório:** `viniciostristao1/adm-projetos` (privado, GitHub)
- **Release APK:** `https://github.com/viniciostristao1/adm-projetos/releases/tag/v0.1.0`

---

## 2. Estrutura de Arquivos (apenas `lib/`)

```
lib/
├── main.dart            # Entry point + temas (Azul/Escuro/Dark Game/Bege)
├── models.dart          # Nota, Projeto — serialização JSON
├── storage.dart         # Persistência local (singleton Storage) + exportarJson/substituir
├── tema.dart            # TemaController (ChangeNotifier) + enums Modo e ModoFonte
├── cores.dart           # AppCores (ThemeExtension) — 8 cores/tema
├── projetos_screen.dart # Tela principal: lista de projetos + busca + backup (export/import)
├── projeto_screen.dart  # Tela de 1 projeto: abas Tarefas/Ideias + _CaixaNota
├── pdf_export.dart      # Gera PDF do projeto inteiro e compartilha (printing)
├── editor.dart          # Utilitários: copiarTexto, mostrarAviso(Acao), capitalizarInicial,
│                        #   proximoNumeroLista, LinhasNumeradas, maiusculaAposItem
└── caixa3d.dart         # Widget simples: Container com cor sólida + borderRadius
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
| `link` | `String?` | `link` (omisso se null) |

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
`azul`, `escuro`, `neumB` (Dark Game), `bege` — **4 temas** (estilo inspirado
no app Calis Timer: azul = navy plano com accent azul; bege = claro com as
cores do tema madeira — tons amadeirados com accent laranja-marrom). Bege é o
único claro (roda em `ThemeMode.light`); os demais são escuros.

- `themeFlutter`: light para `bege`; dark para os demais.
- Seletor de tema na engrenagem: `ChoiceChip` para cada `Modo` (usa `Modo.rotulo`).
- **Migração de temas antigos** (`TemaController.carregar`): `claro` → `azul`;
  `espresso`/`bege`/`begeNeum` → `bege`; padrão (sem preferência) = `azul`.

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

**Bege** — plano, estilo Calis Timer (madeira claro + accent laranja):
| Campo | Hex |
|---|---|
| `notaInicio` / `notaFim` | `#E0D1B9` / `#CBB897` |
| `notaBorda` | `#14000000` |
| `projetoCard` / `projetoCardFim` | `#E0D1B9` / `#D8C7AC` |
| `projetoTxt` | `#382E20` |
| `fab` / `fabIcone` | `#B5652E` / `#FFF3E7` |
| `barraFerramentas` / `barraFerramentasFim` | `#CBB897` / `#CBB897` |
| `fundoInicio` / `fundoFim` | `#D8C7AC` / `#CDBB9D` |
| `textoUI` | `#382E20` |

---

## 5. Fluxo de Telas

```
ProjetosScreen (lista de projetos)
  ├─ FAB [+] → criar projeto
  ├─ 🔍 → busca projetos por nome
  ├─ Card → ProjetoScreen (projeto aberto)
  │    ├─ Tab "Tarefas" → ReorderableListView de _CaixaNota
  │    ├─ Tab "Ideias" → idem
  │    ├─ 🔍 (ao lado das abas) → busca na aba ativa (texto + comentário)
  │    └─ PDF → gera PDF do projeto inteiro e compartilha
  └─ ⚙️ → ConfigSheet (tema, fonte, backup exportar/importar)
```

### Barra de ferramentas da caixinha (`_CaixaNota`)

Barra com rolagem horizontal (o pino de arrastar fica fixo à esquerda). Ordem dos botões (da esquerda para direita, após o pino):

1. `copy_all_outlined` (copiar — botão mais usado, vem primeiro)
2. `check_box` / `check_box_outline_blank` (to-do da caixinha: marcar como feito)
3. `format_list_numbered` / `format_align_justify` (numeração — **só em Tarefas**)
4. `checklist` (inserir item de to-do "☐ ")
5. `arrow_downward` / `arrow_upward` (mover para a outra aba)
6. `unfold_more` (topo/pé do texto)
7. `add_link` (link)
8. `chat_bubble` / `chat_bubble_outline` (comentário inline)
9. `edit_outlined` (focar no fim)
10. `cleaning_services` (limpar)
11. `delete_outline` (excluir, vermelho)

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
- **Tocar no quadradinho** (faixa esquerda de ~40px de uma linha ☐/☑) alterna
  marcado/desmarcado — hit-test com `TextPainter` no `_toqueTexto`, detectado
  por `Listener` (eventos crus, sem disputa de gestos com o campo de texto).

### Caderno (caixinha longa)
- `maxLines: 24`; além disso o texto rola por dentro (Scrollbar).
- Ao GANHAR FOCO, a caixinha rola para cima do botão "+" e a altura do texto é
  travada no espaço disponível (`_alturaMaxima`, recalculada 300ms depois para
  o teclado terminar de abrir). Assim a caixinha NUNCA cresce para trás do FAB
  e a lista NÃO rola a cada tecla (evita o "tremor" durante a digitação).
- ⚠️ A lista NUNCA é puxada (`jumpTo`) enquanto o usuário a rola: isso brigava
  com o dedo, impedia de rolar a página para cima e fazia a tela tremer. Ao
  rolar a lista, só a altura travada é recalculada — e apenas DEPOIS que a
  rolagem para (debounce de 300ms reiniciado a cada evento + checagem de
  `isScrollingNotifier`). O `jumpTo` só acontece ao ganhar foco, ao tocar na
  caixinha (`_toqueTexto`) e quando o teclado abre/fecha.
- Botão `unfold_more` alterna o scroll interno entre topo e pé.

### Desfazer (undo)
- Excluir caixinha, excluir projeto e mover entre abas mostram aviso com **Desfazer** por 4s.
- `mostrarAviso`/`mostrarAvisoAcao` (editor.dart) usam SnackBar **+ Timer** para forçar o fechamento mesmo com animações do sistema desativadas.

### Backup em arquivo (exportar/importar)
- **Exportar:** gera `adm-projetos-backup-AAAA-MM-DD-hhmm.json` (mesmo JSON do Storage) e abre o menu de compartilhamento (`share_plus`).
- **Importar:** escolhe arquivo (`file_picker`), valida o JSON e pergunta: **Substituir tudo** ou **Somar ao que existe** (mescla por id).

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

### Digitação por voz
- O formatador `LinhasNumeradas` só age quando o texto CRESCE e termina com `\n` — não interfere com backspace nem com voz.
- A correção de maiúscula (`maiusculaAposItem`) roda **2 segundos após pausa** na digitação (debounce), não durante — para não quebrar o ditado.

### YouTube Link
- No diálogo de link, ao colar URL do YouTube, após 600ms de pausa busca o título via oEmbed (`youtube.com/oembed`).
- Se encontrado, salva no `comentario` (se vazio) e mostra preview no diálogo.

### Comentário
- Em **Tarefas:** toggle (expande/recolhe sub-caixinha abaixo).
- Em **Ideias:** sempre visível se existir.
- Texto em cor mais fraca (alpha 0.55).

### Backup
- Botão ao lado da engrenagem na tela principal: copia **todos os projetos** (tarefas + futuro) para o clipboard, com separadores `- - -`.

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
  para não sobrescrever comentário salvo por outro caminho (ex.: título do
  YouTube vindo do diálogo de link — `_abrirLink` mantém o controlador em
  sincronia).
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

# Testes (30 testes)
flutter test

# Build local (não usado — build é feito no GitHub Actions)
flutter build apk --release

# Commit + push (usar este padrão)
cd /root/adm-projetos && git add -A && \
  git -c user.name="Vinicius Tristao" -c user.email="viniciostristao@gmail.com" \
  commit -m "<mensagem>" && git push

# Acompanhar build
gh run list --repo viniciostristao1/adm-projetos --limit 1 --json status,conclusion

# Baixar APK da release
gh release download v0.1.0 --repo viniciostristao1/adm-projetos --clobber
```

---

## 9. Padrões de Código

### Adicionar nova cor ao tema
1. Adicionar campo `final Color` em `AppCores` (`cores.dart`)
2. Atualizar construtor, `copyWith`, `lerp`
3. Definir valor nas 4 constantes (`azul`, `escuro`, `neumB`, `bege`)
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
- **flutter_launcher_icons:** `^0.14.4` — gerar ícones do app (dev only)
- Não há pacote `http` — requisições HTTP usam `dart:io` `HttpClient` diretamente.

---

## 10. Testes (30 testes)

### `test/widget_test.dart` (4 testes)
- Serialização de `Nota`
- Serialização de `Projeto` com tarefas
- Projeto com listas vazias
- Migração de dados antigos (`notas` → `tarefas`)

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

### `test/fonte_test.dart` (1 teste)
- O subset embutido (Noto Sans Symbols 2) carrega e renderiza ☐/☑/☒ com glifo real (métrica diferente da fonte de teste — garante que o fallback consulta a fonte e não cai no tofu/emoji)

### `test/tema_test.dart` (6 testes)
- `Modo` tem exatamente os 4 temas (Azul, Escuro, Dark Game, Bege)
- Nomes antigos (claro/bege/begeNeum) não existem mais
- Os 4 temas constroem as superfícies (Caixa3D, BotaoNeum, Fundo, TextField) sem erro

---

## 11. Restrições e Cuidados

- **NÃO usar `http` package** — usar `dart:io` `HttpClient` para requisições (app Android-only, não precisa de compatibilidade web).
- **Não remover `_debounce` de 2s** — necessário para ditado por voz.
- **Não usar `const` com acesso a campo de instância** (ex: `const FloatingActionButtonThemeData(backgroundColor: AppCores.azul.fab)` — dá erro de compilação).
- **Sempre rodar `flutter analyze` antes de commitar** — sem issues.
- **Sempre rodar `flutter test`** — 30 testes devem passar.
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
| 4 temas inspirados no Calis Timer (Azul/Escuro/Dark Game/Bege) | Preferência do usuário; Bege é claro, os demais escuros |
| Keystore fixa (não debug) | Evitar conflito de assinatura entre builds |
| Release `v0.1.0` sobrescrita | Evitar cota de artifacts do GitHub |
| `LinhasNumeradas` age só ao crescer texto | Impede que backspace recrie números |
| Maiúscula com debounce 2s | Não quebrar digitação por voz |
| Abas Tarefas/Ideias | Separar tarefas de ideias futuras |
| `dart:io` em vez de `http` | Não adicionar dependência extra |
| Sem `jumpTo` da lista durante a rolagem do usuário | Era o "tremor" ao rolar a página com uma caixinha focada |
| Derramar controladores no modelo ao perder foco/fechar | Texto em composição da IME não se perde ao sair rápido |
| Nuvem 100% manual (por botão), sem sync automático | Auto-apply da nuvem trocava os objetos do modelo durante a digitação → perda de texto / caixinha excluída voltando (V0.1.24) |
