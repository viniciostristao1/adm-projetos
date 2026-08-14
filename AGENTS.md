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
├── main.dart            # Entry point + 3 ThemeData (claro/escuro/bege)
├── models.dart          # Nota, Projeto — serialização JSON
├── storage.dart         # Persistência local (singleton Storage) + exportarJson/substituir
├── tema.dart            # TemaController (ChangeNotifier) + enums Modo e ModoFonte
├── cores.dart           # AppCores (ThemeExtension) — 8 cores/tema
├── projetos_screen.dart # Tela principal: lista de projetos + busca + backup (export/import)
├── projeto_screen.dart  # Tela de 1 projeto: abas Tarefas/Futuro + _CaixaNota
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
`claro`, `escuro`, `bege` (neumórfico com cartões/barra marrons), `neumB`
(Dark Game), `begeNeum` (Bege Game)

- `themeFlutter`: dark para `escuro`/`neumB`; light para os demais.
- Seletor de tema na engrenagem: `ChoiceChip` para cada `Modo` (usa `Modo.rotulo`).

### Dark Neumorphism (bege, neumB, begeNeum)
- `AppCores.neumorfico == true` habilita superfícies em relevo (luz ↗ superior
  esquerda, sombra dupla difusa, SEM linhas/bordas — o highlight vem do brilho
  difuso).
- `Caixa3D` renderiza gradiente (`notaInicio`→`notaFim`, ou `corInicio`/
  `corFim` quando passados — ex.: cartões de projeto usam `projetoCard`→
  `projetoCardFim`); as cores das sombras/luz vêm de `sombraForte`,
  `sombraFraca`, `brilho` e `bordaLuz` (por paleta).
- Barra de ferramentas: usa gradiente próprio (`barraFerramentas`→
  `barraFerramentasFim`) quando difere da superfície (tema bege = marrom);
  senão segue o gradiente da superfície.
- `BotaoNeum` (caixa3d.dart): botão interativo com estado pressionado (inset
  simulado por gradiente) e `selecionado` (tint do acento).
- `Fundo` (caixa3d.dart): gradiente radial (`fundoInicio`→`fundoFim`) aplicado
  POR TELA, dentro da rota — durante o gesto de voltar, o fundo participa do
  fade junto com o conteúdo (evita efeito "fantasma" da rota anterior).
- Fonte: **Manrope** (variável, asset local) — só nos temas neumórficos.
- FAB: cor `fab` (acento) com elevação 8; abas com indicador "pill" do acento.
- Texto da interface (títulos/abas/chips): `textoUI` — separado de
  `projetoTxt` (texto DENTRO dos cartões) para o caso bege (cartão marrom com
  texto creme + interface marrom escuro sobre fundo claro).

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
| `neumorfico` | bool — ativa relevo neumórfico (A/B/Bege Game) |
| `fundoInicio` / `fundoFim` | Gradiente do fundo do app |
| `sombraForte` / `sombraFraca` | Sombras duplas difusas (cores por tema) |
| `brilho` | Luz refletida no canto superior esquerdo |
| `bordaLuz` | Highlight de 1px (topo/esquerda) |
| `projetoCardFim` | Ponta escura do gradiente do cartão de projeto |
| `barraFerramentasFim` | Ponta escura do gradiente da barra de ferramentas |
| `textoUI` | Texto da interface (títulos, abas, chips) |

### Valores por tema

**Claro:**
| Campo | Hex |
|---|---|
| `notaInicio` | `#F6FAFF` |
| `notaFim` | `#EAF1FA` |
| `notaBorda` | `#1A0B1220` |
| `projetoCard` | `#1E3A8A` |
| `projetoTxt` | `#FFFFFF` |
| `fab` | `#4FC3F7` |
| `fabIcone` | `#0B2E44` |
| `barraFerramentas` | `#1E3A8A` |

**Escuro:**
| Campo | Hex |
|---|---|
| `notaInicio` | `#0A0A0A` |
| `notaFim` | `#0A0A0A` |
| `notaBorda` | `#33FFFFFF` |
| `projetoCard` | `#000000` |
| `projetoTxt` | `#E0E0E0` |
| `fab` | `#F0A500` |
| `fabIcone` | `#1A1200` |
| `barraFerramentas` | `#000000` |

**Bege:**
| Campo | Hex |
|---|---|
| `notaInicio` | `#FFF9F0` |
| `notaFim` | `#F1E9D7` |
| `notaBorda` | `#336D4C2F` |
| `projetoCard` | `#6D4C2F` |
| `projetoTxt` | `#FBF3E8` |
| `fab` | `#6D4C2F` |
| `fabIcone` | `#FBF3E8` |
| `barraFerramentas` | `#6D4C2F` |

---

## 5. Fluxo de Telas

```
ProjetosScreen (lista de projetos)
  ├─ FAB [+] → criar projeto
  ├─ 🔍 → busca projetos por nome
  ├─ Card → ProjetoScreen (projeto aberto)
  │    ├─ Tab "Tarefas" → ReorderableListView de _CaixaNota
  │    ├─ Tab "Futuro" → idem
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
- **Futuro:** sem numeração automática, sem botão de lista.
- Nova caixinha em Tarefas inicia com `"1- "`; Futuro inicia vazio.

### Itens de to-do (quadradinhos ☐/☑)
- Botão `checklist` **converte a LINHA DO CURSOR** em item de to-do (ou remove
  o quadradinho se a linha já for um item) — funciona em qualquer linha, como
  o botão de numeração. Não cria mais linha no fim do texto.
- O Enter continua com `"☐ "` nas linhas seguintes (via `LinhasNumeradas`).
- Os quadradinhos usam `\uFE0E` (VS15) para forçar a apresentação em TEXTO —
  sem isso alguns celulares desenham ☐/☑ como emoji colorido.
- **Tocar no quadradinho** (faixa esquerda de ~40px de uma linha ☐/☑) alterna
  marcado/desmarcado — hit-test com `TextPainter` no `_toqueTexto`, detectado
  por `Listener` (eventos crus, sem disputa de gestos com o campo de texto).

### Caderno (caixinha longa)
- `maxLines: 24`; além disso o texto rola por dentro (Scrollbar).
- Ao GANHAR FOCO, a caixinha rola para cima do botão "+" e a altura do texto é
  travada no espaço disponível (`_alturaMaxima`, recalculada 300ms depois para
  o teclado terminar de abrir). Assim a caixinha NUNCA cresce para trás do FAB
  e a lista NÃO rola a cada tecla (evita o "tremor" durante a digitação).
- Botão `unfold_more` alterna o scroll interno entre topo e pé.

### Desfazer (undo)
- Excluir caixinha, excluir projeto e mover entre abas mostram aviso com **Desfazer** por 4s.
- `mostrarAviso`/`mostrarAvisoAcao` (editor.dart) usam SnackBar **+ Timer** para forçar o fechamento mesmo com animações do sistema desativadas.

### Backup em arquivo (exportar/importar)
- **Exportar:** gera `adm-projetos-backup-AAAA-MM-DD-hhmm.json` (mesmo JSON do Storage) e abre o menu de compartilhamento (`share_plus`).
- **Importar:** escolhe arquivo (`file_picker`), valida o JSON e pergunta: **Substituir tudo** ou **Somar ao que existe** (mescla por id).

### Sincronização com a nuvem (Firebase)
- **`SyncService`** (sync_service.dart, ChangeNotifier): doc `usuarios/{uid}` no
  Firestore com `{dados: JSON, atualizadoEm: ms, email}`.
- Estratégia: **quem salvou por último vence**. Ao entrar: nuvem mais nova →
  baixa e aplica; senão sobe o local. Salvar local → upload com debounce 3s.
  Mudanças remotas aplicadas na hora (eco ignorado via `_ultimoAplicadoMs`).
- **`Storage`** virou `ChangeNotifier` e guarda `ultima_modificacao_ms` no
  SharedPreferences; `marcarModificacaoEm(ms)` usada quando a nuvem baixa.
- `ProjetosScreen` escuta o Storage e recarrega a lista quando a nuvem baixa.
- **Modo local (sem Firebase):** `main()` chama `Firebase.initializeApp()` em
  try/catch — se falhar (google-services.json ausente), o app segue 100%
  local e o botão "Entrar com Google" mostra aviso amigável.
- Login na engrenagem → seção **Nuvem**: Entrar com Google / email + Sair.
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
- Em **Futuro:** sempre visível se existir.
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

# Testes (15 testes)
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
3. Definir valor nas 3 constantes (`luz`, `escuro`, `bege`)
4. Acessar via `Theme.of(context).extension<AppCores>() ?? AppCores.luz`

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

## 10. Testes (15 testes)

### `test/widget_test.dart` (4 testes)
- Serialização de `Nota`
- Serialização de `Projeto` com tarefas
- Projeto com listas vazias
- Migração de dados antigos (`notas` → `tarefas`)

### `test/numeracao_test.dart` (11 testes)
- `proximoNumeroLista`: vazio, sequência existente, sem números
- `LinhasNumeradas`: Enter cria número, sem alteração sem newline, backspace não re-insere, Enter sem número não numera, sequência 1→2→3
- `maiusculaAposItem`: maiúscula após prefixo, já maiúsculo, sem prefixo

---

## 11. Restrições e Cuidados

- **NÃO usar `http` package** — usar `dart:io` `HttpClient` para requisições (app Android-only, não precisa de compatibilidade web).
- **Não remover `_debounce` de 2s** — necessário para ditado por voz.
- **Não usar `const` com acesso a campo de instância** (ex: `const FloatingActionButtonThemeData(backgroundColor: AppCores.luz.fab)` — dá erro de compilação).
- **Sempre rodar `flutter analyze` antes de commitar** — sem issues.
- **Sempre rodar `flutter test`** — 15 testes devem passar.
- **Nunca commitar `android/key.properties` ou `*.jks`** — já no `.gitignore`.
- **Assinatura do APK é fixa** — permite atualizar o app sem desinstalar.

---

## 12. Histórico de Decisões

| Decisão | Motivo |
|---|---|
| JSON local em vez de Firebase | Simplicidade, offline-first, sem custo |
| 3 temas (claro/escuro/bege) | Preferência do usuário |
| Keystore fixa (não debug) | Evitar conflito de assinatura entre builds |
| Release `v0.1.0` sobrescrita | Evitar cota de artifacts do GitHub |
| `LinhasNumeradas` age só ao crescer texto | Impede que backspace recrie números |
| Maiúscula com debounce 2s | Não quebrar digitação por voz |
| Abas Tarefas/Futuro | Separar ideias atuais de futuras |
| `dart:io` em vez de `http` | Não adicionar dependência extra |
