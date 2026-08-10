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
├── storage.dart         # Persistência local (singleton Storage)
├── tema.dart            # TemaController (ChangeNotifier) + enum Modo
├── cores.dart           # AppCores (ThemeExtension) — 8 cores/tema
├── projetos_screen.dart # Tela principal: lista de projetos
├── projeto_screen.dart  # Tela de 1 projeto: abas Tarefas/Futuro + _CaixaNota
├── editor.dart          # Utilitários: copiarTexto, capitalizarInicial,
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

> **Backward compat:** `fromJson` migra chave antiga `notas` → `tarefas`.

---

## 4. Sistema de Temas

### Modo (enum em `tema.dart`)
`claro`, `escuro`, `bege`

### AppCores (ThemeExtension em `cores.dart`)
8 campos de cor por tema:

| Campo | Uso |
|---|---|
| `notaInicio` | Cor da caixinha de texto |
| `notaFim` | Cor final da caixinha (se igual a inicio, tom sólido) |
| `notaBorda` | Borda da caixinha (atualmente não usada no layout) |
| `projetoCard` | Fundo do cartão de projeto na lista principal |
| `projetoTxt` | Cor do texto no cartão de projeto |
| `fab` | Cor de fundo do FAB (botão `+`) |
| `fabIcone` | Cor do ícone no FAB |
| `barraFerramentas` | Cor da barra de ícones no topo de cada caixinha |

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
  ├─ Card → ProjetoScreen (projeto aberto)
  │    ├─ Tab "Tarefas" → ReorderableListView de _CaixaNota
  │    └─ Tab "Futuro" → busca + ReorderableListView de _CaixaNota
  └─ ⚙️ → ConfigSheet (SegmentedButton Claro/Escuro/Bege)
```

### Barra de ferramentas da caixinha (`_CaixaNota`)

Ordem dos botões (da esquerda para direita):
1. `drag_indicator` (arrastar) — canto esquerdo
2. `check_box` / `check_box_outline_blank` (to-do)
3. `format_list_numbered` / `format_align_justify` (lista numerada — **só em Tarefas**)
4. `add_link` (link)
5. `chat_bubble` / `chat_bubble_outline` (comentário inline)
6. `copy_all_outlined` (copiar texto)
7. `edit_outlined` (focar no fim)
8. `cleaning_services` (limpar)
9. `delete_outline` (excluir, vermelho)

---

## 6. Comportamentos Específicos

### Lista numerada
- **Tarefas:** ao pressionar Enter, se a linha anterior é numerada, insere `"N- "` automaticamente. O botão da lista alterna: hora insere linha numerada, hora insere linha em branco.
- **Futuro:** sem numeração automática, sem botão de lista.
- Nova caixinha em Tarefas inicia com `"1- "`; Futuro inicia vazio.

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
- Dentro do `_CaixaNota`, o texto salva com debounce de **2 segundos**.
- Ao fechar a tela ou o widget, força `Storage.instance.salvar()`.

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
