# MUSE — Guia completo para IAs/agentes (voz, pronúncia, memória, modos)

> **Muse Spark** é a assistente de chat de IA do app **Taskix** (este repo, `adm-projetos`).
> Este documento é o **ponto de partida** para qualquer IA/agente que vá mexer na Muse.
> Leia também o `AGENTS.md` (changelog detalhado versão a versão).
>
> **Regra de ouro:** mudar a Muse quase sempre envolve **DOIS lados**. Veja onde cada
> coisa vive antes de editar — alterar só um lado deixa a voz/pronúncia inconsistente.

---

## 1. Arquitetura — os dois lados

| Lado | Onde | O que faz |
|---|---|---|
| **App (Flutter)** | este repo, `lib/chat/` | UI do chat, histórico local, streaming, **voz ON-DEVICE**, digitação por voz, auto-enviar |
| **Proxy (FastAPI)** | **VPS:** `/opt/taskix-chat/` (`app.py`) | monta o prompt, fala com o gateway de IA (OpenCode Go/DeepSeek), `/tts` da VPS (voz **reserva**), conhecimento |

Arquivos do app em `lib/chat/`:
- `chat_screen.dart` — tela, fila de voz, streaming, auto-enviar, normalização de fala do cliente.
- `chat_service.dart` — HTTP: `/chat`, `/chat_stream` (streaming), `/tts` (voz reserva), `enviarStream`/`MuseEvent`.
- `chat_store.dart` — histórico LOCAL (SharedPreferences; **excluído do backup do Android** — ver AGENTS.md).
- `chat_models.dart` — `Conversa`, `ChatMessage`, presets, modelo, tamanho.
- `tts_ondevice.dart` — **voz no próprio celular** (sherpa-onnx + modelo dii).

Proxy na VPS (`/opt/taskix-chat/`):
- `app.py` — tudo do servidor. `conhecimento/` — o que a Muse "sabe".
- Reinícios: `systemctl restart taskix-chat`. Saúde: `curl -s localhost:8092/health`.
- A chave do gateway vive SÓ em `/opt/taskix-chat/.env` (`OPENCODE_GO_API_KEY`). Expira; formato atual `oc_sk_…`.

---

## 2. A VOZ da Muse

- **Voz:** `dii` — **feminina, pt-BR**, modelo **Piper/VITS**. Sotaque aprovado pelo usuário.
- **Repositório do modelo:** release `tts-models` do **sherpa-onnx**:
  `https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-pt_BR-dii-high.tar.bz2` (~67 MB).
  (Origem HF: `csukuangfj/vits-piper-pt_BR-dii-high`.)
- **Dois caminhos de síntese** (a fila tenta on-device primeiro, senão servidor):
  1. **ON-DEVICE (preferido)** — `lib/chat/tts_ondevice.dart` (`TtsOnDevice`): baixa o modelo 1× (guarda em `<docs>/tts_dii/`), roda `OfflineTts` do pacote `sherpa_onnx`. **Rápido e offline.** `preparar()` baixa/carrega; `sintetizar(texto)→WAV`.
  2. **SERVIDOR (reserva)** — `POST /tts` no `app.py` (roda o Piper `pt_BR-dii-high.onnx` em `/opt/taskix-chat/vozes/`). Usado enquanto o on-device não baixou, ou se ele falhar. Reserva do reserva: faber (masculino), Edge (bloqueado na VPS), gTTS.
- **Por que on-device:** a VPS tem 1 vCPU (síntese lenta, ~2,5s/parágrafo + rede = ~7s). No celular é bem mais rápido e offline, e não sobrecarrega a VPS/auto-trader.
- **Build:** deps `sherpa_onnx` + `archive` no `pubspec.yaml`; `abiFilters = arm64-v8a, armeabi-v7a` em `android/app/build.gradle.kts` (sem x86 p/ não inflar o APK; APK fica ~174 MB). Modelo **NÃO** é embutido (baixado na 1ª vez).

---

## 3. VELOCIDADE da fala — onde mudar (⚠️ DOIS lugares)

A velocidade é o `length_scale` (↑ = mais LENTA; ↓ = mais rápida). **Mude nos dois** para manter igual:

1. **On-device:** `lib/chat/tts_ondevice.dart` → `static const double _lengthScale = 1.04;`
2. **Servidor:** `/opt/taskix-chat/vozes/pt_BR-dii-high.onnx.json` → campo `inference.length_scale` (ex.: `1.04`). Depois `systemctl restart taskix-chat` (ou só recarrega no próximo pedido, pois o Piper lê o json por chamada).

Valor atual: **1.04**. Histórico: 1.10 (lento demais) → 1.04 → 1.02 → **1.04** (pedido do usuário). Regra prática: ajustes de ±2% por vez (ex.: 1.02→1.04 ≈ 2% mais lento).

---

## 4. PRONÚNCIA — como corrigir (⚠️ DOIS lugares)

Como a síntese pode ocorrer no celular (que **não** passa pelo servidor), a correção de pronúncia é replicada:

1. **Servidor:** `app.py` → dicionário `PRONUNCIA_FALA` + função `_aplicar_pronuncia`.
2. **App (on-device):** `lib/chat/chat_screen.dart` → função `_normalizarFala` (o mapa `mapa` + as regras regex).

**Mantenha os dois em sincronia.** Só afeta a FALA — a escrita na tela fica intacta.

### Como corrigir uma palavra / sílaba tônica
O truco é **reescrever a palavra como ela deve SOAR**, usando acentos pt-BR para marcar a **sílaba tônica** (o espeak/pt lê a grafia). Exemplos já configurados:

| Palavra (escrita) | Grafia na FALA | Por quê |
|---|---|---|
| bike | `báik` | soar como o inglês /baɪk/ |
| delay | `delei` | idem |
| halter / halteres | `altér` / `altéres` | tônica no "é", sem o "h" |
| rep / reps | `repetição` / `repetições` | expandir abreviação |

**Para ADICIONAR uma palavra:** inclua a mesma entrada nos DOIS lugares:
- `app.py`: `PRONUNCIA_FALA = { …, "palavra": "grafía_que_soa_certo" }` → `systemctl restart taskix-chat`.
- `chat_screen.dart`: no `const mapa = { …, 'palavra': 'grafía_que_soa_certo' }` de `_normalizarFala` → rebuild do app.
- Dica de tônica: use acento agudo/circunflexo na vogal tônica ("altér", "cardió", "ênfase"). Teste de ouvido e ajuste a grafia (é iterativo).

### Regras especiais de fala (já implementadas, nos dois lados)
- **"NxM" → "N de M"**: "3x7" é lido "três de sete" (notação séries×repetições). Regex `(\d+)\s*[xX]\s*(\d+)` → `\1 de \2`.
- **Nome sem pausa de vírgula:** "boa noite, Vinícios" → fala "boa noite Vinícios" (tira a vírgula antes do nome). Regex `,\s*(Vin[ií]ci[ou]s)` → ` \1`.

---

## 5. Pausas, parágrafos e entonação (streaming)
- A Muse fala **por PARÁGRAFO** (não por frase), com uma fila **produtor-consumidor** (`_vozSintese` sintetiza adiantado, `_vozPlay` toca) → entonação de pergunta correta e **sem vão** entre trechos.
- Uma 1ª linha curta (título/saudação) **junta com o parágrafo seguinte** (>=80 chars) p/ não "secar" antes do próximo ficar pronto.
- Servidor: pausa de ponto curta via `--sentence_silence 0.05` no Piper; parágrafos "colados" na fala (`\n+`→espaço). O `maxNumSenetences` e `silenceScale` do sherpa-onnx ficam no padrão.
- Limite conhecido: em resposta curta, o texto gera antes de a voz sair (~0,5–1s de síntese). On-device reduz muito isso.

---

## 6. Digitação por voz (Dictate) + auto-enviar
- O usuário digita por voz com o **teclado Dictate** (Whisper offline) — é um teclado do sistema; o app só recebe o TEXTO inserido (não "vê" o botão do mic).
- **Modo áudio** (segurar o botão de enviar → ícone 🎤): liga (a) **auto-play** da resposta falando e (b) **auto-enviar**.
- **Auto-enviar** (`_aoDigitarVoz` + `_autoSendTimer` em `chat_screen.dart`): no modo áudio, quando o texto para de mudar por **~0,6s** (você soltou o mic), ENVIA sozinho → semi-conversa hands-free (ditar → envia → responde falando). O tempo (600 ms) é tunável.

---

## 7. MEMÓRIA e CONHECIMENTO da Muse — como adicionar info pessoal

Tudo vive em **`/opt/taskix-chat/conhecimento/`** (a Muse lê a cada mensagem; não precisa reiniciar). Ver também `conhecimento/INSTRUCOES.md`.

| Arquivo | Usado no modo | Conteúdo |
|---|---|---|
| `pessoal.md` | **Geral** (e Coach) | dados pessoais, rotina, objetivos, **com DATAS `[AAAA-MM-DD]`** |
| `perfil.md` | **Coach** | alimentação habitual + **equipamentos** (ex.: halteres) |
| `projetos.md` | **Projetos** | estado dos apps/projetos do usuário (curado, sem segredos) |
| `calis_*.md`, `livros.md` | Coach | ciência de treino, índice de livros |
| `INSTRUCOES.md` | — | guia de edição do conhecimento (para IA/usuário via Termius) |

**Fluxo para adicionar info pessoal** (ex.: novo equipamento, nova preferência):
1. Abra o arquivo certo (`perfil.md` p/ comida/equipamento; `pessoal.md` p/ rotina/pessoal).
2. Acrescente **uma linha com data** `[AAAA-MM-DD] …`. Não apague o histórico; só adicione.
3. Pronto — a Muse já considera na próxima mensagem (lê por requisição).
4. **Nunca** colocar segredos/chaves/IPs/estratégia de trading (o texto vai ao gateway externo).

A Muse também tem **memória episódica** automática (aprende 1 fato por troca; ver `INSTRUCOES.md` → "memória episódica"). O proxy injeta a **data/hora de hoje** (Brasília) e o **carimbo por mensagem** p/ ela entender "ontem/hoje/amanhã".

### Horário de sono (lembrete de dormir)
Em `app.py` → `_nivel_sono`: seg–qui sinaliza ≥20:45 e enfatiza ≥21:15; **sexta e sábado** mais tarde (sinal ≥21:30, enfático ≥22:00); domingo sem cutucada.

---

## 8. Modos (preset) da Muse
Selecionável por conversa (menu). Em `chat_models.dart` (`ChatPreset`) e no `app.py` (montagem do prompt):
- **Coach (Calis)** — treinador do Calis Timer: lê o desempenho (Firestore) + `perfil.md`/ciência. Foco principal.
- **Projetos** — discute os apps/projetos (usa `projetos.md`).
- **Geral** — conversa livre/pessoal (usa `pessoal.md`).
Também: **modelo** (rápido/caprichado — DeepSeek flash) e **tamanho** (longo/curto) por conversa.

---

## 9. Checklist para outro agente contribuir
1. **App:** editar `lib/…`, rodar `flutter analyze` (limpo) + `flutter test` (142+ testes) — Flutter em `/root/flutter/bin` (`export PATH="$PATH:/root/flutter/bin"`).
2. **Versão:** subir `lib/versao.dart` + `version:` do `pubspec.yaml` (ex.: `0.1.131+131`).
3. **Release:** commit + push na `main` → GitHub Actions compila o APK → link
   `https://github.com/viniciostristao1/adm-projetos/releases/download/v0.1.0/taskix-v0.1.<N>.apk`. **Sempre mandar o link ao usuário.** Instalar POR CIMA (não desinstalar).
4. **Proxy:** editar `/opt/taskix-chat/app.py` → `systemctl restart taskix-chat` → conferir `/health`. ⚠️ **NÃO sobrecarregar a VPS** (1 vCPU/3,8 GB; auto-trader no mesmo servidor): build de APK é só no CI; nada de rodar modelos pesados residentes sem avaliar memória.
5. **Pronúncia/velocidade:** lembrar dos **dois lados** (seções 3 e 4).
6. **Não** commitar segredos; `.env` fica só na VPS.

---

## 10. Histórico
Changelog detalhado por versão: `AGENTS.md` (seção "Módulo de chat / Muse"). Resumo da jornada da voz: V0.1.102 (TTS inicial) → V0.1.122 (voz feminina dii) → V0.1.126–130 (streaming, por parágrafo, auto-enviar, pronúncia) → **V0.1.131 (voz ON-DEVICE offline)**.
