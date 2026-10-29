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
- `conversas_screen.dart` — **LISTA de conversas** (a aba "Muse" abre AQUI; V0.1.173).
- `chat_service.dart` — HTTP: `/chat`, `/chat_stream` (streaming), `/tts` (voz reserva), `enviarStream`/`MuseEvent`.
- `chat_store.dart` — histórico LOCAL (SharedPreferences; **excluído do backup do Android** — ver AGENTS.md).
- `chat_models.dart` — `Conversa`, `ChatMessage`, presets, modelo, tamanho.
- `tts_ondevice.dart` — **voz no próprio celular** (sherpa-onnx + modelo dii).
- `chat_actions.dart` — blocos da Muse: `[[ACAO:…]]` (lembrete/nota) e `[[SUGESTOES:…]]` (`QuickReplies`, respostas de 1 toque).

> **UI V0.1.173 (fora de `lib/chat/`):** o app abre no `HomeShell`
> (`lib/home_shell.dart`) com barra inferior flutuante **Projetos · Muse ·
> Estudos**; a aba Muse abre a LISTA (`ConversasScreen`) e o chat tem **voltar ←
> → lista**. Topo do chat: **←**, **☰** (buscar/nova/resumo/renomear/modelo/
> tamanho/fala) e **M** (modo). O rosto da Muse é o `MuseBlob`
> (`lib/muse_blob.dart`, tingido no acento do tema). **Respostas de 1 toque:** o
> app mostra até 2 chips acima da caixa a partir do bloco `[[SUGESTOES: a | b]]`.
> Esse bloco vem de duas formas no `app.py`: (1) o modelo emite (`_SUGESTOES`); (2)
> **fallback determinístico** — em QUASE TODA resposta (não só perguntas; pula
> resumo/erro/curtas), se o modelo NÃO emitiu, o servidor GERA as 2 opções numa
> chamada curta dedicada (`_com_sugestoes`/`_gerar_sugestoes`): responde à pergunta
> OU dá continuações naturais. O (2) garante que as sugestões apareçam sempre (o
> modelo esquece a regra após alguns turnos) — e é só servidor, vale no APK atual.

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

## 3. VELOCIDADE e VOZ da fala — onde mudar

A velocidade é o `length_scale` (↑ = mais LENTA; ↓ = mais rápida) e agora é
**configurável pelo usuário** (não mais constante no código):

1. **App:** `lib/voz_config.dart` (`VozController`: `voz_velocidade_v1` 0.85–1.25,
   padrão **1.04**; `voz_id_v1` 'dii'/'faber') + seção "Voz da Muse" nas
   Configurações (slider + Feminina/Masculina) + "Fala devagar" por conversa
   (menu ⋮ da Muse, `Conversa.falaDevagar`, soma +0.16).
2. **On-device:** `TtsOnDevice.sintetizar(texto, velocidade:)` — o isolate
   RECRIA o motor se a velocidade mudar entre pedidos (sem derrubar a fila).
3. **Servidor:** `POST /tts` aceita `{voz: "dii"|"faber"|voz Edge, velocidade}` —
   Piper usa o modelo faber/dii + flag `--length_scale` (faixa 0.7–1.4).
   Sem parâmetros = comportamento antigo (.onnx.json).

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
 | arrego / arregos | `arrêgo` / `arrêgos` | tônica na 2ª sílaba (ê fechado) |
 | schopenhauer | `chopenrráuer` | nome próprio alemão aportuguesado |
 | nietzsche | `níti` | simplificado a pedido do usuário |
 | haha (risada) | `rá rá rá` | risada soletrada com pausas |

**Para ADICIONAR uma palavra:** inclua a mesma entrada nos DOIS lugares:
- `app.py`: `PRONUNCIA_FALA = { …, "palavra": "grafía_que_soa_certo" }` → `systemctl restart taskix-chat`.
- `chat_screen.dart`: no `const mapa = { …, 'palavra': 'grafía_que_soa_certo' }` de `_normalizarFala` → rebuild do app.
- Dica de tônica: use acento agudo/circunflexo na vogal tônica ("altér", "cardió", "ênfase"). Teste de ouvido e ajuste a grafia (é iterativo).

### Regras especiais de fala (já implementadas, nos dois lados)
- **"NxM" → "N de M"**: "3x7" é lido "três de sete" (notação séries×repetições). Regex `(\d+)\s*[xX]\s*(\d+)` → `\1 de \2`.
- **"kg" → "quilo(s)"**: "2 kg"→"2 quilos", "1 kg"→"1 quilo". Regex `\b(\d+)\s*kg\b` (pluraliza) + `\bkg\b`→"quilos".
- **Nome sem pausa de vírgula:** "boa noite, Vinícios" → fala "boa noite Vinícios" (tira a vírgula antes do nome). Regex `,\s*(Vin[ií]ci[ou]s)` → ` \1`.
- **Despedidas naturais** (persona, `app.py`): votos como "bom café/bom treino/bom descanso" em vez de construções tortas ("vai bem no café").

---

## 5. Pausas, parágrafos e entonação (streaming)
- A Muse fala **por PARÁGRAFO** (não por frase), com uma fila **produtor-consumidor** (`_vozSintese` sintetiza adiantado, `_vozPlay` toca) → entonação de pergunta correta e **sem vão** entre trechos.
- Uma 1ª linha curta (título/saudação) **junta com o parágrafo seguinte** (>=80 chars) p/ não "secar" antes do próximo ficar pronto.
- Servidor: pausa de ponto curta via `--sentence_silence 0.05` no Piper; parágrafos "colados" na fala (`\n+`→espaço). O `maxNumSenetences` e `silenceScale` do sherpa-onnx ficam no padrão.
- Limite conhecido: em resposta curta, o texto gera antes de a voz sair (~0,5–1s de síntese). On-device reduz muito isso.

---

## 6. Entrada por voz / texto — campo + coluna (anexo em cima, enviar embaixo)
A barra de entrada é **[campo de texto, 3–10 linhas com scrollbar] [coluna: anexar pequeno em cima, botão único grande embaixo]**. O botão de enviar faz as duas coisas pelo gesto (`chat_screen.dart`, no `_barraEntrada` — `GestureDetector` + `FloatingActionButton` normal 56px, ícone 28):
- **TOQUE curto** (`FAB.onPressed`) → envia o **texto digitado**. Põe `_modoAudio=false` → resposta vem em **texto** (sem voz; toque o alto-falante p/ ouvir).
- **SEGURAR** (`onLongPressStart`→`_micStart`; `onLongPressEnd`→`_micStop`) → **grava por voz** (botão fica vermelho, ícone 🎤), transcreve ao vivo; ao **SOLTAR**, para e **envia na hora**, e a resposta vem **FALANDO** (`_micStart` põe `_modoAudio=true` → voz→voz).

A voz de entrada é o reconhecimento **NATIVO do Android** (`speech_to_text`; motor do Google, mesmo do Gboard; **instantâneo**, não usa o teclado). `_stt.stop()` + ~350 ms p/ o resultado final → `_enviar`. Permissão `RECORD_AUDIO` + `<queries>` do `RecognitionService` no `AndroidManifest.xml`. Trata soltar durante o init (`_micSegurando`). Pontuação: o motor do Google pontua pouco — mas a IA entende sem (ver §4 nota).

**Regra de auto-play:** segue o MÉTODO de entrada — falou (🎤) → responde falando; digitou (toque) → responde em texto. Não há mais um "modo áudio" persistente nem auto-enviar-por-pausa (removidos; o botão único cobre tudo). Teclado de voz (Dictate/Gboard) ainda funciona: você digita por voz e dá o **toque curto** p/ enviar.

**Alarmes inteligentes (V0.1.172):** lembrete com `abrir`+`dizer` (`[[ACAO:lembrete … | abrir=coach|projetos|geral | dizer=<pergunta>]]`, ensinado no `_ACAO` do proxy) — tocar no corpo da notificação abre o chat naquele modo e **envia a pergunta sozinho** (conversa nova; `ChatScreen(presetInicial, perguntaInicial)`; roteamento via pedido em prefs + notify em `LembretesService`). Snooze preserva o payload. Botão **"Feito ✓"** na notificação conclui sem abrir o app (nunca cancela série recorrente/backup semanal).

**Resumo semanal (V0.1.172, servidor):** `resumo_semanal.py` — 1x/semana, domingo 06–22h (estado por semana ISO), injeta o fechamento (treinos, joelho se mencionado, leitura, foco seguinte) quando conecta com o assunto. Testes em `tests_resumo_semanal.py`.

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
Selecionável por conversa pelo botão **M** no canto superior direito do chat
(V0.1.173 — mostra a inicial do modo atual, C/P/G, tingida no acento; toca e
troca). Em `chat_models.dart` (`ChatPreset`) e no `app.py` (montagem do prompt):
- **Coach (Calis)** — treinador do Calis Timer: lê o desempenho (Firestore) + `perfil.md`/ciência. Foco principal.
- **Projetos** — discute os apps/projetos (usa `projetos.md`).
- **Geral** — conversa livre/pessoal (usa `pessoal.md`).

### Modelo de IA (gateway OpenCode Go) — qual está em uso
O app manda o `model` por conversa; o proxy valida contra `MODELOS_OK` (`app.py`). Selecionável no menu **⋮ → Modelo** (`ChatModelo` em `chat_models.dart`):
- **Padrão = `deepseek-v4.1-flash`** — com visão (testada). Definido no `/opt/taskix-chat/.env` → `OPENCODE_GO_MODEL`.
- **Fallback = `glm-5.3-flash`** (`OPENCODE_FALLBACK`) — usado se o escolhido falhar (barato; `qwen3.8-flash` é a 2ª opção testada e OK).
- `MAX_TOKENS=4000`, `REASONING_EFFORT=none` (desliga raciocínio oculto → ~metade do tempo).

⚠️ **2026-10-27: `deepseek-v4-flash-vision-exp` e `deepseek-flash` MORRERAM no gateway** (`HTTP 410 ModelDeprecated`; o gateway sugere `deepseek-v4.1-flash`). Sintoma era "A IA está indisponível agora" (proxy 502) nas conversas com modelo Rápido — o Caprichado (v4.1-flash) seguia funcionando. Fix só no servidor: `.env` (`MODEL`+`FALLBACK`), `MODELOS_OK` e `VISION_MODEL` (`tem visão`) em `app.py`, restart. Conversas antigas salvas com o id morto caem no `MODEL` atual (allowlist) — funcionam sem atualizar o app; o rótulo "Rápido" no menu ⋮ ficou desatualizado (trocar o id em `chat_models.dart` exige APK novo).

⚠️ **`muse-spark-1.3-contributor` NÃO funciona** neste gateway (testado 2026-10-12 **e de novo 2026-10-20**: `HTTP 400 ModelProtocolUnsupported` — é um endpoint de outro protocolo, não um modelo chat-completions; `muse-spark-1.3` dá "Model is unavailable"). Por isso a Muse usa **DeepSeek**. Para adicionar como 3ª opção, só se o gateway passar a expô-lo como chat-completions.

⚠️ **`gpt-5.6-luna` (GPT da OpenAI) — mesma história (experimento 2026-10-24).** No `chat/completions` dá **`400 ModelProtocolUnsupported`** → cai no DeepSeek (fallback). **Causa real:** o Luna (e o muse-spark) só falam a **Responses API** do gateway: `POST https://opencode.ai/zen/go/v1/responses` com `{"model","input":<messages>,"max_output_tokens"}` — **sem `temperature`** (modelos GPT novos rejeitam: "Unsupported parameter: 'temperature'"); a resposta vem em `output[].content[].text` e o uso em `usage.input_tokens/output_tokens`. Testado: `/responses` devolve **200**. **Implicação:** selecionar Luna no Cread/Muse HOJE **roda DeepSeek** (fallback) — pra usar de verdade precisa rotear modelos GPT pelo `/responses` (ai.py do Cread e `_call_gateway` do proxy). **Custo (2026-10, OpenCode Zen, por 1M tokens):** Luna $0,20 in / $1,20 out · DeepSeek v4.1-flash $0,30 / $1,20 · v4-pro $1,74 / $3,48 → **Luna é até mais barato que o flash na entrada**; custo não é barreira. **Comparação Muse (persona+`.md`, preset geral):** no papel de coach/neurociência o **DeepSeek se saiu igual ou melhor** (mais detalhe + puxou dados pessoais do `.md`); o Luna foi mais enxuto/fluido, porém mais raso. Para **escrita longa (livros, no Cread)** o Luna pode ganhar — tarefa diferente, não testada aqui. Cache de contexto funciona nos dois (visto `cached_tokens` na 2ª msg).

Também: **tamanho** (longo/curto) por conversa.

---

## 9. Checklist para outro agente contribuir
1. **App:** editar `lib/…`, rodar `flutter analyze` (limpo) + `flutter test` (142+ testes) — Flutter em `/root/flutter/bin` (`export PATH="$PATH:/root/flutter/bin"`).
2. **Versão:** subir SÓ o `version:` do `pubspec.yaml` + rodar `dart tool/gerar_versao.dart` (o `lib/versao.dart` é gerado; o CI gera de novo a cada build).
3. **Release:** commit + push na `main` → GitHub Actions compila o APK → link
   `https://github.com/viniciostristao1/adm-projetos/releases/download/v0.1.0/taskix-v0.1.<N>.apk`. **Sempre mandar o link ao usuário.** Instalar POR CIMA (não desinstalar).
4. **Proxy:** editar `/opt/taskix-chat/app.py` → `systemctl restart taskix-chat` → conferir `/health`. ⚠️ **NÃO sobrecarregar a VPS** (1 vCPU/3,8 GB; auto-trader no mesmo servidor): build de APK é só no CI; nada de rodar modelos pesados residentes sem avaliar memória.
5. **Pronúncia:** lembrar dos **dois lados** (seção 4). Velocidade/voz vêm das
   Configurações (`lib/voz_config.dart`, seção 3) — não há mais constante espalhada.
6. **Não** commitar segredos; `.env` fica só na VPS.

---

## 10. Histórico
Changelog detalhado por versão: `AGENTS.md` (seção "Módulo de chat / Muse"). Resumo da jornada da voz: V0.1.102 (TTS inicial) → V0.1.122 (voz feminina dii) → V0.1.126–130 (streaming, por parágrafo, auto-enviar, pronúncia) → **V0.1.131 (voz ON-DEVICE offline)**.
