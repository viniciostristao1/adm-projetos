import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../diagnostico.dart';
import '../cores.dart';
import '../storage.dart';
import '../sync_service.dart';
import '../voz_config.dart';
import 'chat_models.dart';
import 'chat_actions.dart';
import 'chat_service.dart';
import 'chat_store.dart';
import 'tts_ondevice.dart';

/// Janela do Muse (assistente de chat do Taskix) — módulo isolado, só aberto pelo
/// botão de mensagem (que só existe com a flag `CHAT`). Auth = login Google que o
/// app já usa (`SyncService`); o servidor só aceita a conta do dono. Tem histórico
/// de conversas (local).
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  final _scroll = AutoScrollController();
  final _foco = FocusNode();
  // Scroll INTERNO da caixa de mensagem (TextField 1→5 linhas): quando o ditado
  // passa de 5 linhas, o texto novo desce para fora da viewport da caixa — sem
  // isso o usuário não vê o que acabou de ser capturado. Mantemos no fim.
  final _caixaScroll = ScrollController();
  final _buscaCtrl = TextEditingController();
  bool _buscando = false; // modo busca na conversa
  String _busca = '';
  List<(int, int)> _hits = []; // ocorrências: (índice da mensagem, posição no texto)
  int _hitAtual = -1;
  Conversa _conv = Conversa.nova(ChatPreset.coach);
  bool _enviando = false;
  bool _carregando = true;
  Timer? _tick; // atualiza o contador do "pensando"
  // Botão de GRAVAÇÃO (push-to-talk TRAVADO) com o reconhecimento de voz NATIVO
  // do Android (motor do Google, mesmo do Gboard — instantâneo): fala→texto no app.
  // SEGURAR inicia e TRAVA (soltar NÃO para — o botão não foge mais do dedo quando
  // a caixa cresce); TOQUE no enviar conclui e envia; TOQUE na caixa para a
  // gravação mantendo o texto (p/ corrigir na hora, sem perder largura da caixa).
  // Não depende do teclado de voz (Dictate/Gboard).
  final SpeechToText _stt = SpeechToText();
  bool _sttOk = false; // inicializado com sucesso
  bool _gravando = false; // ouvindo (gravação ativa, TRAVADA até enviar/toque)
  // Ditado CONTÍNUO (textos longos): o reconhecedor do Android para sozinho em
  // pausa longa (~3s padrão) ou após dezenas de segundos — sem restart o texto
  // truncava no meio da frase. `_paradaManual` distingue "sistema parou" (=
  // recomeça sozinho) de "usuário parou" (enviar/toque/limpar = não recomeça).
  // `_textoBase` acumula o já ditado entre sessões (o recognizer zera o texto
  // a cada restart — sem acumular, o recomeço apagaria o início).
  bool _paradaManual = false;
  String _textoBase = '';
  bool _reabrindoVoz = false; // debounce da reabertura ativa (erro transitório)
  // (v0.1.161 testou reconhecimento ON-DEVICE p/ tolerar pausas longas como o
  // Gboard, mas no aparelho do usuário PIOROU — cortava até ao respirar — então
  // foi revertido na v0.1.162. Pausas bem longas = usar o mic do Gboard na caixa.)
  // Sessão do ditado: cada SEGURAR gera um id novo e cada PARADA (enviar/toque/
  // limpar/sair/erro permanente) invalida o id atual. Resultado ATRASADO do STT
  // (o `stop()` entrega um onResult final DEPOIS de limpar/enviar) com id velho
  // é descartado — sem isso o transcrito voltava sozinho p/ a caixa vazia após
  // o envio, quando a Muse já estava respondendo.
  int _sessaoVoz = 0;
  // Vigia anti-mic-morto: o Android pode encerrar a sessão SEM avisar via status
  // (aí o botão fica vermelho mas nada mais é transcrito). A cada 2s confere se
  // houve evento recente do reconhecedor; sem evento há 6s, força um recomeço
  // limpo (cancel + listen). `_ultimoEventoVozAt` é carimbado em todo onResult
  // e status. Só anda com gravação ativa.
  Timer? _vigiaVoz;
  int _ultimoEventoVozAt = 0;
  DateTime? _inicioEnvio;
  String? _anexo; // texto anexado (clip) p/ a próxima mensagem
  final List<String> _imagensB64 = []; // imagens anexadas (visão), máx. 3
  static const int _maxImagens = 3;
  final FlutterTts _tts = FlutterTts();
  int? _lendoIdx; // índice da mensagem que está sendo lida (TTS)
  final AudioPlayer _vozNeural = AudioPlayer(); // MP3 da voz neural (/tts)
  bool _gerandoVoz = false; // buscando o áudio (mostra ampulheta)
  // PAUSA da leitura (botão do alto-falante): pausa de verdade e retoma de onde
  // parou (player.pause/resume). Diferente de parar (que zera a fila).
  bool _pausado = false; // leitura pausada (retomável)
  bool _pausaChunkTts = false; // o trecho pausado era do TTS do aparelho (re-fala ele)
  bool _trocandoVoz = false; // troca play/pause/stop em voo (ignora toques duplos)
  // MODO ÁUDIO (segurar o botão enviar): a resposta da Muse toca sozinha, sem
  // tocar no alto-falante — semi-conversação (você dita no Gboard, ela responde
  // em texto + voz). Fica salvo só em memória (default desligado a cada abertura).
  bool _modoAudio = false;
  // Token p/ cancelar/validar a reprodução por frases (streaming): cada nova fala
  // incrementa; loops antigos param ao ver o token mudar.
  int _falaToken = 0;
  // STREAMING da resposta (fala enquanto escreve): a resposta chega frase a frase.
  bool _streamando = false;
  String _streamTexto = ''; // resposta parcial sendo recebida (balão ao vivo)
  String _proxSep = ' '; // separador antes da próxima frase ('\n\n' após parágrafo)
  String _vozParag = ''; // parágrafo em montagem p/ a voz (fala por PARÁGRAFO, não frase)
  StreamSubscription<MuseEvent>? _subStream;
  // Fila de voz PRODUTOR-CONSUMIDOR: a SÍNTESE roda ADIANTADA (um trecho por vez,
  // sem contenção de CPU) e fica À FRENTE da reprodução → começa cedo e sem vão
  // entre trechos. Vale pro streaming (por parágrafo) e pro replay (toque manual).
  final List<String> _vozTextos = []; // textos a falar, na ordem
  final List<Uint8List?> _vozAudios = []; // áudios já sintetizados (alinhado a _vozTextos); null = falhou
  int _vozTocarIdx = 0; // próximo índice a tocar
  bool _vozSintetizando = false;
  bool _vozTocando = false;
  int? _vozMsgIdx; // se a fila é de um REPLAY de mensagem, qual índice (p/ limpar o ícone no fim)

  /// Ícone de cada modo.
  static IconData _icone(ChatPreset p) => switch (p) {
        ChatPreset.coach => Icons.fitness_center,
        ChatPreset.projetos => Icons.folder_outlined,
        ChatPreset.geral => Icons.forum_outlined,
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SyncService.instance.addListener(_aoMudarAuth);
    _configTts();
    _tts.setCompletionHandler(() {
      // Só limpa o ícone se a fila já acabou (sem isso, um trecho de fallback
      // do TTS concluído no MEIO da fila apagava o ícone com a leitura rolando).
      if (mounted &&
          _vozTocarIdx >= _vozTextos.length &&
          !_vozSintetizando) {
        setState(() => _lendoIdx = null);
      }
    });
    // A conclusão da voz neural é gerida pelo streaming em `_falar` (o listener
    // global zerava o _lendoIdx no fim de CADA frase, cortando a leitura).
    _foco.addListener(_aoMudarFocoCaixa);
    _carregar();
    // Pré-aquece em 2º plano (sem snack, sem bloquear): reconhecimento de voz +
    // voz offline. Assim o 1º segurar já grava e a 1ª resposta já sai rápida.
    // O microfone pode pedir permissão aqui; se negada, tentamos de novo no segurar.
    WidgetsBinding.instance.addPostFrameCallback((_) => _preAquecerVoz());
  }

  /// Foco na caixa de mensagem → rola a conversa p/ a última ficar acima do
  /// teclado (o teclado encolhe a lista mas mantém o offset antigo, escondendo
  /// o fim). O 2º scroll cobre a animação de abertura do teclado (~300ms).
  void _aoMudarFocoCaixa() {
    if (_foco.hasFocus) {
      _rolarFim();
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted && _foco.hasFocus) _rolarFim();
      });
    }
  }

  @override
  void didChangeMetrics() {
    // Teclado abriu/fechou ou a caixa cresceu (1→5 linhas): mantém o fim visível
    // acima do teclado/caixa. Sem isso a última mensagem fica escondida atrás.
    if (mounted && !_carregando) _rolarFim();
  }

  /// Prepara STT + voz offline sem snack e sem travar a UI (fire-and-forget).
  Future<void> _preAquecerVoz() async {
    try {
      if (!_sttOk) {
        try {
          _sttOk = await _stt.initialize(
            onStatus: _aoStatusStt,
            onError: _aoErroStt,
          );
        } catch (_) {
          _sttOk = false;
        }
      }
    } catch (_) {}
    try {
      // Não mostra "baixando/voz pronta": usa servidor como reserva silenciosa.
      await TtsOnDevice.preparar();
    } catch (_) {}
  }

  /// TTS em pt-BR, voz FEMININA já instalada (não baixa nada; se não houver, usa
  /// a padrão do aparelho). Pitch levemente acima p/ soar mais natural/feminino.
  Future<void> _configTts() async {
    await _tts.setLanguage('pt-BR');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.08);
    try {
      final voices = await _tts.getVoices as List?;
      for (final v in voices ?? const []) {
        final m = Map<String, dynamic>.from(v as Map);
        final loc = '${m['locale']}'.toLowerCase();
        final nome = '${m['name']}'.toLowerCase();
        final fem = '${m['gender']}'.toLowerCase() == 'female' ||
            nome.contains('female') ||
            nome.contains('#f');
        if (loc.startsWith('pt') && fem) {
          await _tts.setVoice(
              {'name': '${m['name']}', 'locale': '${m['locale']}'});
          break;
        }
      }
    } catch (_) {}
  }

  /// Para qualquer leitura em curso (neural ou do aparelho) e invalida o stream.
  /// Zera a fila (não é retomável — para pausar sem perder o ponto, ver `_pausarFala`).
  Future<void> _pararFala() async {
    _falaToken++; // invalida sínteses/reproduções em andamento
    _vozTextos.clear();
    _vozAudios.clear();
    _vozTocarIdx = 0;
    _vozSintetizando = false;
    _vozTocando = false;
    _vozMsgIdx = null;
    _vozParag = '';
    _pausado = false;
    _pausaChunkTts = false;
    try {
      await _tts.stop();
    } catch (e, st) {
      Diagnostico.registrar('voz-stop', e, st);
    }
    try {
      await _vozNeural.stop();
    } catch (e, st) {
      Diagnostico.registrar('voz-stop', e, st);
    }
  }

  /// Sintetiza um trecho: tenta NO APARELHO (sherpa-onnx/dii, rápido e offline) e,
  /// se não estiver pronto/falhar, cai no /tts da VPS (reserva). Respeita a voz e
  /// o ritmo das Configurações (+ "devagar" desta conversa). A masculina (faber)
  /// só existe no servidor — pula o on-device direto.
  Future<Uint8List?> _sintetizarTrecho(String texto) async {
    final v = vozController.velocidade +
        (_conv.falaDevagar ? VozController.devagarDelta : 0.0);
    if (!vozController.masculina && TtsOnDevice.pronto) {
      final b = await TtsOnDevice.sintetizar(_normalizarFala(texto),
          velocidade: v);
      if (b != null) return b;
    }
    // Servidor aplica a própria normalização.
    return ChatService.audioNeural(texto,
        voz: vozController.masculina ? 'faber' : null, velocidade: v);
  }

  /// Taxa do TTS do aparelho (último fallback): 0.5 é o padrão; acompanha o
  /// ritmo configurado (lengthScale maior = fala mais devagar = taxa menor).
  double _taxaFalaTts() {
    final v = vozController.velocidade +
        (_conv.falaDevagar ? VozController.devagarDelta : 0.0);
    return (0.5 * VozController.velocidadePadrao / v).clamp(0.1, 1.0).toDouble();
  }

  /// Normalização de fala do CLIENTE (p/ a síntese on-device, que não passa pelo
  /// /tts) — espelha o dicionário do servidor: NxM→"N de M", bike→báik, etc.
  String _normalizarFala(String t) {
    t = t.replaceAllMapped(
        RegExp(r'(\d+)\s*[xX]\s*(\d+)'), (m) => '${m[1]} de ${m[2]}');
    // Contagens hifenizadas de UM dígito ("4-7-8", "4-4") → "4, 7, 8" (pausa curta
    // entre números, sem ler "menos"). Restrito a 1 dígito p/ não quebrar datas,
    // telefones e intervalos.
    t = t.replaceAllMapped(
        RegExp(r'\b(\d(?:\s*-\s*\d)+)\b'),
        (m) => m[1]!.replaceAll(RegExp(r'\s*-\s*'), ', '));
    // "kg" (unidade) → "quilo(s)": "2 kg"→"2 quilos", "1 kg"→"1 quilo".
    t = t.replaceAllMapped(RegExp(r'\b(\d+)\s*kg\b'),
        (m) => '${m[1]} quilo${m[1] == "1" ? "" : "s"}');
    t = t.replaceAll(RegExp(r'\bkg\b'), 'quilos');
    // Vocativo: tira a vírgula antes do nome ("boa noite, Vinícios" → "…Vinícios").
    t = t.replaceAllMapped(
        RegExp(r',\s*(Vin[ií]ci[ou]s)\b', caseSensitive: false),
        (m) => ' ${m[1]}');
    const mapa = {
      'bike': 'báik', 'bikes': 'báiks',
      'delay': 'delei', 'delays': 'deleis',
      'rep': 'repetição', 'reps': 'repetições',
      'halter': 'altér', 'halteres': 'altéres',
      'arrego': 'arrêgo', 'arregos': 'arrêgos',
      'app': 'ép', 'apps': 'éps',
      'foram': 'fôram',
      'hmm': 'hum', 'hm': 'hum',
      'clean': 'clin', 'and': 'end',
      'schopenhauer': 'chopenrráuer', 'nietzsche': 'níti',
      'nietzschiano': 'nitiano', 'nietzscheano': 'nitiano',
      'fati': 'fáti',
      'haha': 'rá rá rá',
    };
    mapa.forEach((p, g) {
      t = t.replaceAllMapped(
          RegExp('\\b$p\\b', caseSensitive: false), (_) => g);
    });
    return t;
  }

  /// Prepara a voz on-device em silêncio (sem snack, sem bloquear). Enquanto não
  /// fica pronta, a resposta usa a voz do servidor como reserva. Chamado ao
  /// segurar p/ gravar / tocar no alto-falante. O pré-aquecimento real acontece
  /// em `_preAquecerVoz()` (abertura da tela); aqui é só reforço.
  Future<void> _prepararVozOffline() async {
    if (TtsOnDevice.pronto) return;
    try {
      await TtsOnDevice.preparar();
    } catch (_) {}
  }

  /// Enfileira um trecho (frase/parágrafo) p/ falar e aciona os dois workers.
  void _enfileirarVoz(String trecho) {
    _vozTextos.add(trecho);
    _vozSintese();
    _vozPlay();
  }

  /// WORKER DE SÍNTESE: sintetiza os trechos UM A UM (sem contenção de CPU),
  /// ADIANTADO em relação à reprodução. Como o Piper é ~5× mais rápido que o
  /// tempo real, o áudio do próximo fica pronto antes de o atual acabar = sem vão.
  Future<void> _vozSintese() async {
    if (_vozSintetizando) return;
    _vozSintetizando = true;
    final token = _falaToken;
    while (_vozAudios.length < _vozTextos.length) {
      if (token != _falaToken || !mounted) break;
      final bytes = await _sintetizarTrecho(_vozTextos[_vozAudios.length]);
      if (token != _falaToken || !mounted) break;
      _vozAudios.add(bytes);
      _vozPlay(); // pode haver áudio novo pronto p/ tocar
    }
    if (token == _falaToken) _vozSintetizando = false;
  }

  /// WORKER DE REPRODUÇÃO: toca os áudios já sintetizados, EM ORDEM.
  /// Qualquer exceção de player/TTS é engolida (troca rápida play/stop/pause no
  /// Android solta PlatformException — sem o try/catch o app CRASHA com o
  /// "Taskix parou de funcionar").
  Future<void> _vozPlay() async {
    if (_vozTocando) return;
    _vozTocando = true;
    final token = _falaToken;
    while (_vozTocarIdx < _vozAudios.length) {
      if (token != _falaToken || !mounted) break;
      // Pausado: estaciona aqui até retomar/parar (não toca o próximo trecho).
      while (_pausado && token == _falaToken && mounted) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (token != _falaToken || !mounted) break;
      final i = _vozTocarIdx;
      final bytes = _vozAudios[i];
      _vozTocarIdx++;
      if (mounted && _gerandoVoz) setState(() => _gerandoVoz = false); // 1º áudio saiu
      if (bytes == null || bytes.isEmpty) {
        try {
          // Teto de 60s por trecho: se o motor do aparelho travar, não prende
          // a fila inteira (os trechos seguintes continuam).
          // NORMALIZA aqui também: sem isso o fallback do flutter_tts falava o
          // texto CRU (ex.: "Schopenhauer" na 1ª palavra, antes do Piper esquentar,
          // saía "chopenráuer" fraco; no meio já vinha sintetizado e correto).
          // A taxa acompanha o ritmo configurado (+ "devagar" da conversa).
          await _tts.setSpeechRate(_taxaFalaTts());
          await _tts
              .speak(_normalizarFala(_vozTextos[i]))
              .timeout(const Duration(seconds: 60), onTimeout: () {});
        } catch (e, st) {
          Diagnostico.registrar('voz-tts', e, st);
        }
        continue;
      }
      final done = Completer<void>();
      final sub = _vozNeural.onPlayerComplete.listen((_) {
        if (!done.isCompleted) done.complete();
      });
      try {
        try {
          await _vozNeural.play(BytesSource(bytes));
        } catch (e, st) {
          Diagnostico.registrar('voz-play', e, st);
          if (!done.isCompleted) done.complete(); // não trava a fila
        }
        while (!done.isCompleted) {
          if (token != _falaToken || !mounted) break;
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } finally {
        try {
          await sub.cancel();
        } catch (_) {}
      }
    }
    _vozTocando = false;
    // Terminou TUDO (tocou todos e a síntese acabou)? Se for um replay, limpa o ícone.
    if (token == _falaToken &&
        _vozTocarIdx >= _vozTextos.length &&
        !_vozSintetizando &&
        _vozMsgIdx != null) {
      if (mounted) {
        setState(() {
          _lendoIdx = null;
          _gerandoVoz = false;
          _pausado = false;
          _pausaChunkTts = false;
        });
      }
      _vozMsgIdx = null;
    }
  }

  /// Remove carimbo de data/hora que possa ter vazado no INÍCIO de mensagens
  /// (ex.: "[23:40]", "[hoje 23:16] [16/10 …]"). Novas respostas já vêm limpas do
  /// servidor; isto cobre as ANTIGAS na escrita E na fala. Exige hora (HH:MM),
  /// hoje/ontem ou dd/MM dentro do colchete p/ preservar "[📷 imagem]" etc.
  String _semCarimbo(String t) => t.replaceFirst(
      RegExp(
          r'^\s*(?:\[[^\]]*(?:\d{1,2}:\d{2}|hoje|ontem|\d{1,2}/\d{1,2})[^\]]*\]\s*)+',
          caseSensitive: false),
      '');

  /// Lê a resposta da Muse em voz alta (ou pausa/retoma). Toca por PARÁGRAFO pela
  /// fila produtor-consumidor: começa após o 1º parágrafo (não espera sintetizar
  /// a mensagem inteira) e os seguintes já vêm prontos. A prosódia do Piper fica
  /// natural, sem as emendas da leitura frase-a-frase. Cai para o TTS do aparelho
  /// se a voz neural falhar. Toques duplos durante a troca são ignorados.
  ///  • tocou em outra mensagem → para a atual e começa a nova;
  ///  • tocou na que está tocando → PAUSA (retomável);
  ///  • tocou na pausada → RETOMA de onde parou;
  ///  • SEGUROU na que está tocando/pausada → PARA de vez.
  Future<void> _falar(int idx, String texto) async {
    if (_trocandoVoz) return; // troca em voo: ignora o toque duplo
    if (_lendoIdx == idx && _pausado) {
      await _retomarFala();
      return;
    }
    if (_lendoIdx == idx) {
      await _pausarFala();
      return;
    }
    _trocandoVoz = true;
    try {
      await _pararFala();
      TtsOnDevice.preparar(); // carrega a voz on-device (se ainda não) p/ o replay
      if (mounted) {
        setState(() {
          _lendoIdx = idx;
          _gerandoVoz = true; // buscando o 1º áudio
        });
      }
      // Toca por PARÁGRAFO pela fila produtor-consumidor: começa após o 1º parágrafo
      // (não espera sintetizar a mensagem inteira) e os seguintes já vêm prontos.
      final pars = _semCarimbo(texto)
          .split(RegExp(r'\n\s*\n'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      if (pars.isEmpty) {
        if (mounted) {
          setState(() {
            _lendoIdx = null;
            _gerandoVoz = false;
          });
        }
        return;
      }
      _vozMsgIdx = idx; // é um replay desta msg → limpa o ícone quando acabar
      for (final p in pars) {
        _enfileirarVoz(p);
      }
    } finally {
      _trocandoVoz = false;
    }
  }

  /// Pausa a leitura mantendo o ponto (retomável com `_retomarFala`). Não zera a
  /// fila nem invalida a síntese adiantada — o worker estaciona no trecho atual.
  Future<void> _pausarFala() async {
    if (_trocandoVoz || _lendoIdx == null || _pausado) return;
    _trocandoVoz = true;
    try {
      // Se o trecho atual é do TTS do aparelho (sem áudio neural), ele será
      // interrompido pelo stop — na retomada esse trecho é re-falado do início.
      final cur = _vozTocarIdx - 1;
      _pausaChunkTts = cur >= 0 &&
          cur < _vozAudios.length &&
          (_vozAudios[cur] == null || _vozAudios[cur]!.isEmpty);
      try {
        await _vozNeural.pause();
      } catch (e, st) {
        Diagnostico.registrar('voz-pause', e, st);
      }
      try {
        await _tts.stop();
      } catch (e, st) {
        Diagnostico.registrar('voz-pause', e, st);
      }
      if (mounted) setState(() => _pausado = true);
    } finally {
      _trocandoVoz = false;
    }
  }

  /// Retoma a leitura exatamente de onde pausou.
  Future<void> _retomarFala() async {
    if (_trocandoVoz || _lendoIdx == null || !_pausado) return;
    _trocandoVoz = true;
    try {
      if (_pausaChunkTts) {
        // O trecho pausado era do TTS (foi parado): volta 1 posição p/ re-falá-lo.
        final cur = _vozTocarIdx - 1;
        if (cur >= 0 && cur < _vozTextos.length) {
          _vozTocarIdx = cur;
          _pausaChunkTts = false;
          _vozPlay(); // garante o worker andando (pode ter terminado o loop)
        }
      } else {
        try {
          await _vozNeural.resume();
        } catch (e, st) {
          Diagnostico.registrar('voz-resume', e, st);
        }
      }
      if (mounted) setState(() => _pausado = false);
    } finally {
      _trocandoVoz = false;
    }
  }

  /// Para de vez a leitura da mensagem (segurar o botão do alto-falante).
  Future<void> _pararReplay() async {
    if (_trocandoVoz || _lendoIdx == null) return;
    _trocandoVoz = true;
    try {
      await _pararFala();
      if (mounted) {
        setState(() {
          _lendoIdx = null;
          _gerandoVoz = false;
        });
      }
    } finally {
      _trocandoVoz = false;
    }
  }

  /// Recomeça a leitura desta mensagem do INÍCIO — mesmo que já esteja tocando ou
  /// pausada. Botão dedicado à esquerda do alto-falante: o alto-falante continua
  /// sendo tocar/pausar; este sempre reinicia do zero.
  Future<void> _recomecarFala(int idx, String texto) async {
    if (_trocandoVoz) return;
    if (_lendoIdx != null) await _pararReplay(); // zera fila/estado atual
    _pausado = false; // garante começar do zero (não "retomar" de onde parou)
    await _falar(idx, texto);
  }

  /// No MODO ÁUDIO, dispara a leitura automática da última resposta da Muse.
  void _autoFalar() {
    if (!_modoAudio || _conv.mensagens.isEmpty) return;
    final i = _conv.mensagens.length - 1;
    if (_conv.mensagens[i].ehUsuario) return;
    _falar(i, _conv.mensagens[i].texto);
  }

  Future<void> _carregar() async {
    final convs = await ChatStore.listar();
    final ult = await ChatStore.ultimaId();
    if (!mounted) return;
    setState(() {
      if (convs.isNotEmpty) {
        // Reabre a ÚLTIMA conversa usada (não sempre a mesma).
        _conv = convs.firstWhere((c) => c.id == ult, orElse: () => convs.first);
      }
      _carregando = false;
    });
    // Abre direto na 1ª linha da última resposta (sem animação de scroll).
    _abrirNoFim();
    // Reatar a um envio em voo (perguntou e saiu com voltar no meio): primeiro o
    // STREAMING (frase a frase); senão o envio normal (futuro único).
    final stream = ChatService.streamPendente(_conv.id);
    if (stream != null) {
      setState(() {
        _enviando = true;
        _streamando = true;
        _streamTexto = '';
      });
      _escutarStream(_conv.id, stream, const [], null);
    } else {
      final pend = ChatService.pendenteDe(_conv.id);
      if (pend != null) await _reatachar(pend);
    }
  }

  /// Reanexa a um envio que continua em background (a tela saiu com voltar no
  /// meio da resposta): mostra o "pensando" e aplica a resposta ao chegar.
  Future<void> _reatachar(Future<ChatResult> pend) async {
    if (_enviando) return;
    final idOrigem = _conv.id;
    setState(() {
      _enviando = true;
      _inicioEnvio = DateTime.now();
    });
    _rolarFim(); // mira no "pensando"
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
    final res = await pend;
    _tick?.cancel();
    if (!mounted) return;
    if (_conv.id != idOrigem) {
      setState(() => _enviando = ChatService.pendenteDe(_conv.id) != null);
      return;
    }
    if (res.sucesso) {
      final atual = await ChatStore.porId(idOrigem);
      if (!mounted) return;
      if (atual != null) setState(() => _conv = atual);
    } else {
      setState(() {
        _conv.mensagens = [..._conv.mensagens, ChatMessage.ia('⚠️ ${res.erro}')];
      });
      await ChatStore.salvar(_conv);
    }
    if (!mounted) return;
    setState(() => _enviando = false);
    // Resposta chegou: mostra a 1ª linha dela (p/ começar lendo de cima).
    _rolarFim(inicioResposta: true);
    if (res.sucesso) _autoFalar(); // modo áudio: lê a resposta automaticamente
  }

  // Salva ao ir para SEGUNDO PLANO (paused/detached): no Android o `dispose` NÃO
  // dispara quando o app é mandado pra background e depois morto pelo sistema —
  // sem isto, o estado em memória da sessão se perdia. Com o merge do ChatStore,
  // salvar aqui é seguro (nunca encolhe o que já está salvo).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (!_conv.vazia) {
        ChatStore.salvar(_conv);
        ChatStore.marcarUltima(_conv.id);
      }
      // Saiu do app no meio da leitura: pausa (retomável ao voltar) em vez de
      // deixar tocando sozinha ou cortar de vez.
      if (_lendoIdx != null && !_pausado && !_trocandoVoz) _pausarFala();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SyncService.instance.removeListener(_aoMudarAuth);
    _foco.removeListener(_aoMudarFocoCaixa);
    _tick?.cancel();
    _paradaManual = true; // impede restart do ditado ao sair
    _sessaoVoz++; // invalida resultados atrasados
    _vigiaVoz?.cancel();
    _vigiaVoz = null;
    _stt.cancel();
    _falaToken++; // invalida workers de voz em voo
    _pausado = false;
    _subStream?.cancel(); // o stream segue vivo no ChatService e salva ao fim
    try {
      _tts.stop();
    } catch (_) {}
    _vozNeural.dispose();
    _buscaCtrl.dispose();
    // Ao sair, salva a conversa atual e marca como a última (reabre nela depois).
    // Vai para a fila do ChatStore (não dá p/ esperar no dispose); como todo
    // envio já salva com await, aqui é só reforço.
    if (!_conv.vazia) {
      ChatStore.salvar(_conv); // fila: não bloquear o dispose (segue em background)
      ChatStore.marcarUltima(_conv.id);
    }
    _ctrl.dispose();
    _scroll.dispose();
    _caixaScroll.dispose();
    _foco.dispose();
    super.dispose();
  }

  void _aoMudarAuth() {
    if (mounted) setState(() {});
  }

  // Rola o INTERIOR da caixa de mensagem até o fim (última linha visível).
  // O TextField com maxLines:10 cria um scroll interno quando o texto passa de
  // 10 linhas; a atualização programática (_ctrl.text = ...) NÃO acompanha o
  // cursor sozinha — sem isto o texto novo desce para baixo da caixa e o usuário
  // não vê o que foi capturado. ⚠️ Chamar SÓ quando o cursor está no fim
  // (ditado e digitação no fim): chamar no onTap ou em digitação no MEIO do
  // texto joga a caixa p/ baixo e esconde o trecho que o usuário tocou/editou.
  void _rolarCaixaFim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_caixaScroll.hasClients) return;
      final pos = _caixaScroll.position;
      if (pos.pixels < pos.maxScrollExtent) {
        _caixaScroll.jumpTo(pos.maxScrollExtent);
      }
    });
  }

  // Rola até a ÚLTIMA mensagem (via scrollToIndex — confiável mesmo fora da tela,
  // inclusive ao abrir, resolvendo o "abriu na penúltima"). Enquanto envia, mira no
  // item EXTRA do "pensando" (índice n) p/ o contador ficar visível sem rolagem manual.
  // `instantaneo` (1ms — o pacote proíbe duração zero) = abrir direto, sem ver a
  // conversa "correndo". `inicioResposta` = mostra a PRIMEIRA linha da última resposta
  // da IA (p/ começar lendo de cima); com msg sua por último, mostra o fim como antes.
  void _rolarFim({bool instantaneo = false, bool inicioResposta = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final n = _conv.mensagens.length;
      if (n > 0 && _scroll.hasClients) {
        final alvo = n - 1 + (_enviando ? 1 : 0);
        final pos = (inicioResposta &&
                !_enviando &&
                !_conv.mensagens.last.ehUsuario)
            ? AutoScrollPosition.begin
            : AutoScrollPosition.end;
        _scroll.scrollToIndex(alvo,
            preferPosition: pos,
            duration: Duration(milliseconds: instantaneo ? 1 : 250));
      }
    });
  }

  // Abre a conversa JÁ posicionada na última resposta da Muse SEM "rolar" a
  // conversa inteira. `scrollToIndex` percorre a lista passo a passo até um índice
  // distante (a rolagem que o usuário via ao abrir); `jumpTo` NÃO anima. Então:
  // (1) salta instantaneamente até o fim, repetindo enquanto a lista lazy ainda
  // cresce o maxScrollExtent (o extent é estimado e refina a cada frame);
  // (2) no fim, se a última mensagem é da Muse, alinha a 1ª LINHA dela ao topo
  // (movimento curto — o item já está na viewport). Usado só ao ABRIR/trocar de
  // conversa (no envio a lista já está embaixo, aí o _rolarFim curto basta).
  void _abrirNoFim([int tentativas = 8]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final pos = _scroll.position;
      if (tentativas > 0 && pos.pixels < pos.maxScrollExtent - 1) {
        _scroll.jumpTo(pos.maxScrollExtent);
        _abrirNoFim(tentativas - 1);
        return;
      }
      final n = _conv.mensagens.length;
      if (n > 0 && !_enviando && !_conv.mensagens.last.ehUsuario) {
        _scroll.scrollToIndex(n - 1,
            preferPosition: AutoScrollPosition.begin,
            duration: const Duration(milliseconds: 1));
      }
    });
  }

  // ───────── Botão de gravação (voz nativa do Android → texto → envia) ─────────
  /// SEGURAR inicia e TRAVA a gravação (soltar o dedo NÃO para). O ditado é
  /// CONTÍNUO: o Android para sozinho em pausas/teto de sessão — o `_aoStatusStt`
  /// recomeça automaticamente acumulando em `_textoBase`. A parada é explícita
  /// (toque em enviar, X ou limpar). Transcreve ao vivo.
  Future<void> _micStart() async {
    if (_enviando || _gravando) return;
    // Feedback IMEDIATO (antes de qualquer await): o botão fica vermelho na hora,
    // mesmo na 1ª vez (quando o STT ainda está inicializando). Sem isso o segurar
    // parecia "não fazer nada" e o usuário soltava.
    _paradaManual = false;
    _textoBase = '';
    _ctrl.clear();
    _ultimoEventoVozAt = DateTime.now().millisecondsSinceEpoch;
    _vigiaVoz?.cancel();
    if (mounted) {
      setState(() {
        _gravando = true;
        _modoAudio = true; // usar o mic = conversa: a resposta toca em voz
      });
    } else {
      _gravando = true;
      _modoAudio = true;
    }
    if (!_sttOk) {
      try {
        _sttOk = await _stt.initialize(
          onStatus: _aoStatusStt,
          onError: _aoErroStt,
        );
      } catch (_) {
        _sttOk = false;
      }
      if (!_sttOk) {
        _paradaManual = true;
        if (mounted) setState(() => _gravando = false);
        _snack('Reconhecimento de voz indisponível neste aparelho');
        return;
      }
    } else {
      // Garante os handlers atuais (o pré-aquecimento pode ter registrado outros).
      try {
        await _stt.initialize(
          onStatus: _aoStatusStt,
          onError: _aoErroStt,
        );
      } catch (_) {}
    }
    // Travado: mesmo que o dedo já tenha soltado durante a inicialização/permissão,
    // a gravação continua — a parada é explícita (toque em enviar ou X).
    _prepararVozOffline(); // garante a voz da resposta pronta (silenciosa)
    final sessao = ++_sessaoVoz; // id deste ditado (resultados velhos são descartados)
    Diagnostico.registrar('voz', 'inicio');
    _vigiaVoz = Timer.periodic(
        const Duration(seconds: 2), (_) => _vigiarVoz(sessao));
    _ouvirUmaVez(sessao);
  }

  /// Uma sessão de escuta (o sistema pode encerrar sozinho — ver `_aoStatusStt`).
  /// `listenFor` longo evita o teto de ~30s; `pauseFor` longo tolera pausas para
  /// pensar no meio de frases longas; `cancelOnError:false` não morre em falha
  /// transitória (o restart cuida). `sessao` invalida resultados atrasados de um
  /// ditado já encerrado (ver `_sessaoVoz`). Falha ao abrir = 1 retry em 1s (o
  /// vigia cobre o resto).
  Future<void> _ouvirUmaVez(int sessao) async {
    if (sessao != _sessaoVoz ||
        !_gravando ||
        _paradaManual ||
        !mounted ||
        _stt.isListening) {
      return;
    }
    try {
      await _stt.listen(
        onResult: (r) {
          if (sessao != _sessaoVoz || _paradaManual || !_gravando) return;
          _ultimoEventoVozAt = DateTime.now().millisecondsSinceEpoch;
          final atual = r.recognizedWords.trim();
          if (r.finalResult) {
            // Só metadados (sem o texto falado): o relatório pode ser
            // compartilhado sem expor o conteúdo ditado.
            Diagnostico.registrar(
                'voz', 'final len=${atual.length} base=${_textoBase.length}');
          }
          // Parcial vazio nunca apaga: no fim da sessão o reconhecedor costuma
          // emitir um resultado vazio — sem este guarda ele ZERAVA a caixa e o
          // `_aoStatusStt` comitava o vazio como base (ditado "recomeçava").
          if (atual.isEmpty) return;
          final combinado =
              _textoBase.isEmpty ? atual : '$_textoBase $atual';
          // Nunca encolhe: resultado atrasado/ revisado p/ menos não pode apagar
          // o que já estava transcrito (a pausa p/ pensar não apaga nada).
          if (combinado.length < _ctrl.text.length) return;
          _ctrl.text = combinado;
          _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
          // Caixa: mostra sempre o fim do que foi capturado (últimas linhas).
          _rolarCaixaFim();
          // Conversa: mantém o fim visível acima do teclado/caixa.
          _rolarFim(instantaneo: true);
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: false,
          listenFor: Duration(seconds: 120),
          pauseFor: Duration(seconds: 8),
          localeId: 'pt_BR',
        ),
      );
    } catch (e, st) {
      // Falha ao (re)começar (reconhecedor ocupado encerrando a sessão
      // anterior): 1 retry em 1s; o vigia (`_vigiarVoz`) cobre o resto.
      Diagnostico.registrar('voz', 'listen-falhou: $e', st);
      final s2 = sessao;
      Future.delayed(const Duration(seconds: 1), () {
        if (s2 == _sessaoVoz &&
            _gravando &&
            !_paradaManual &&
            mounted &&
            !_stt.isListening) {
          _ouvirUmaVez(s2);
        }
      });
    }
  }

  /// Vigia anti-mic-morto (a cada 2s com gravação ativa): sem nenhum evento do
  /// reconhecedor há 6s, a sessão travou em silêncio (o Android encerrou sem
  /// status e o botão segue vermelho sem transcrever). Força recomeço limpo:
  /// cancela (o que atualiza o `isListening` travado) e escuta de novo.
  Future<void> _vigiarVoz(int sessao) async {
    if (sessao != _sessaoVoz ||
        !_gravando ||
        _paradaManual ||
        !mounted) {
      _vigiaVoz?.cancel();
      _vigiaVoz = null;
      return;
    }
    final paradoHa =
        DateTime.now().millisecondsSinceEpoch - _ultimoEventoVozAt;
    // 3s (era 6s): recupera mais rápido um encerramento silencioso do Android —
    // o restart ativo do erro transitório (_reabrirVoz) cobre o caso comum da
    // pausa curta; o vigia é só o backstop para a morte sem status nem erro.
    if (paradoHa < 3000) return;
    Diagnostico.registrar('voz', 'watchdog: $paradoHa ms sem evento, recomeçando');
    try {
      await _stt.cancel();
    } catch (e, st) {
      Diagnostico.registrar('voz', 'watchdog-cancel: $e', st);
    }
    await Future.delayed(const Duration(milliseconds: 300));
    _ouvirUmaVez(sessao);
  }

  /// Status do reconhecedor: `done`/`notListening` com gravação ativa e sem
  /// parada manual = o sistema encerrou a sessão sozinho (pausa/teto) → comita
  /// o parcial como base e recomeça para o ditado continuar de onde parou.
  void _aoStatusStt(String s) {
    _ultimoEventoVozAt = DateTime.now().millisecondsSinceEpoch;
    if (!_gravando || _paradaManual || !mounted) return;
    if (s == 'done' || s == 'notListening') {
      // Metadados p/ diagnóstico (sem o texto): ajuda a ver no relatório se o
      // restart está acontecendo a cada pausa.
      Diagnostico.registrar(
          'voz', 'status=$s base=${_textoBase.length}c caixa=${_ctrl.text.length}c');
      if (_ctrl.text.trim().isNotEmpty) _textoBase = _ctrl.text.trim();
      final sessao = _sessaoVoz;
      // Pequeno respiro antes de reabrir (evita loop apertado em erro contínuo).
      Future.delayed(const Duration(milliseconds: 300), () {
        if (sessao == _sessaoVoz &&
            _gravando &&
            !_paradaManual &&
            mounted &&
            !_stt.isListening) {
          _ouvirUmaVez(sessao);
        }
      });
    }
  }

  /// Erro do reconhecedor: transitório ignora (o status recomeça); permanente
  /// (sem permissão/mic) encerra com aviso.
  void _aoErroStt(dynamic e) {
    _ultimoEventoVozAt = DateTime.now().millisecondsSinceEpoch;
    try {
      final perm = (e as dynamic).permanent as bool?;
      Diagnostico.registrar('voz', 'erro perm=$perm: $e');
      if (perm == true) {
        _paradaManual = true;
        _sessaoVoz++; // invalida resultados atrasados deste ditado
        _vigiaVoz?.cancel();
        _vigiaVoz = null;
        if (mounted) setState(() => _gravando = false);
        _snack('Reconhecimento de voz indisponível neste aparelho');
      } else {
        // Transitório = o caso da PAUSA CURTA: o reconhecedor nativo dispara
        // no-match / speech-timeout e MORRE, mas com `cancelOnError:false` o
        // plugin às vezes NÃO emite `done` → `_aoStatusStt` não recomeça e a
        // captação ficava numa ZONA MORTA até o vigia (6s), truncando a fala.
        // Agora reabrimos a escuta JÁ (acumulando em `_textoBase`), então uma
        // pausa de 1–2s não interrompe o ditado. Ver _reabrirVoz.
        _reabrirVoz(_sessaoVoz);
      }
    } catch (_) {}
  }

  /// Reabre a escuta após o reconhecedor nativo encerrar numa pausa curta
  /// (erro transitório). Cancela o estado preso (o `cancelOnError:false` pode
  /// deixar `isListening` em true), guarda o parcial em `_textoBase` e volta a
  /// ouvir — fechando a zona morta sem esperar o vigia. Debounced para não
  /// empilhar reaberturas quando chegam vários erros seguidos.
  Future<void> _reabrirVoz(int sessao) async {
    if (_reabrindoVoz) return;
    if (sessao != _sessaoVoz || !_gravando || _paradaManual || !mounted) return;
    _reabrindoVoz = true;
    if (_ctrl.text.trim().isNotEmpty) _textoBase = _ctrl.text.trim();
    try {
      await _stt.cancel();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 180));
    _reabrindoVoz = false;
    if (sessao == _sessaoVoz &&
        _gravando &&
        !_paradaManual &&
        mounted &&
        !_stt.isListening) {
      Diagnostico.registrar('voz', 'reabrir (pausa/erro transitório)');
      _ouvirUmaVez(sessao);
    }
  }

  /// TOQUE no enviar com gravação ativa → para de ouvir e ENVIA.
  Future<void> _micStop() async {
    if (!_gravando) return;
    _paradaManual = true; // impede o auto-restart do `_aoStatusStt`
    _vigiaVoz?.cancel();
    _vigiaVoz = null;
    try {
      await _stt.stop();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 350));
    // A partir daqui, qualquer onResult final atrasado do STT é descartado
    // (sessão invalidada) — sem isso ele repovoava a caixa logo após o envio.
    _sessaoVoz++;
    _textoBase = '';
    if (!mounted) return;
    setState(() => _gravando = false);
    if (!_enviando && _ctrl.text.trim().isNotEmpty) _enviar();
  }

  /// Toque na caixa com gravação ativa → para de ouvir SEM enviar (mantém o texto
  /// p/ editar). Equivale ao antigo X lateral (removido p/ não estreitar a caixa).
  Future<void> _micCancel() async {
    if (!_gravando) return;
    _paradaManual = true;
    _sessaoVoz++;
    _textoBase = '';
    _vigiaVoz?.cancel();
    _vigiaVoz = null;
    try {
      await _stt.cancel();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _gravando = false);
  }

  /// X da caixa de mensagem → limpa tudo o que está escrito/ditado (texto +
  /// anexo + imagens). Se estava gravando, para primeiro sem enviar. Mantém o
  /// foco na caixa p/ continuar digitando/ditando na sequência.
  Future<void> _limparCaixa() async {
    _paradaManual = true;
    _sessaoVoz++;
    _textoBase = '';
    _vigiaVoz?.cancel();
    _vigiaVoz = null;
    if (_gravando) {
      try {
        await _stt.cancel();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _gravando = false;
      _ctrl.clear();
      _anexo = null;
      _imagensB64.clear();
    });
    _rolarCaixaFim();
    _foco.requestFocus();
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    final texto = capitalizarFrases(_ctrl.text.trim());
    final imgs = List<String>.from(_imagensB64);
    if (texto.isEmpty && _anexo == null && imgs.isEmpty) return;
    // Junta o anexo (clip) e/ou as imagens à mensagem, se houver.
    var conteudo = _anexo == null
        ? texto
        : (texto.isEmpty ? _anexo! : '$texto\n\n--- Anexo ---\n${_anexo!}');
    if (imgs.isNotEmpty) {
      final marca =
          imgs.length == 1 ? '[📷 imagem anexada]' : '[📷 ${imgs.length} imagens anexadas]';
      conteudo = conteudo.isEmpty ? marca : '$conteudo\n$marca';
    }
    _ctrl.clear();
    await _pararFala(); // zera qualquer leitura/fila de voz anterior
    setState(() {
      _conv.mensagens = [..._conv.mensagens, ChatMessage.usuario(conteudo)];
      _conv.talvezTitular();
      _enviando = true;
      _streamando = true;
      _streamTexto = '';
      _proxSep = ' ';
      _vozParag = '';
      _inicioEnvio = DateTime.now();
      _anexo = null;
      _imagensB64.clear();
    });
    // Conta o tempo de espera (até a 1ª frase chegar), atualizando a cada 100ms.
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
    await ChatStore.salvar(_conv);
    await ChatStore.marcarUltima(_conv.id);
    _rolarFim();

    // Envio em STREAMING: a resposta chega FRASE A FRASE (fala enquanto escreve).
    // A consumição vive no ChatService (sobrevive ao voltar) e salva no store ao
    // terminar. Se o stream falhar ANTES de qualquer frase, cai no envio normal.
    final idOrigem = _conv.id;
    final snapshot = List<ChatMessage>.from(_conv.mensagens);
    final imgsEnvio = imgs.isEmpty ? null : imgs;
    _escutarStream(
      idOrigem,
      ChatService.enviarStream(idOrigem, snapshot,
          presetId: _conv.preset.id,
          modeloId: _conv.modelo.id,
          tamanhoId: _conv.tamanho.id,
          imagensB64: imgsEnvio),
      snapshot,
      imgsEnvio,
    );
    _foco.requestFocus();
  }

  /// Escuta o stream de frases: mostra o texto ao vivo + fala por frase (modo
  /// áudio). Ao concluir, recarrega a conversa do store (fonte da verdade).
  void _escutarStream(String idOrigem, Stream<MuseEvent> stream,
      List<ChatMessage> snapshot, List<String>? imgs) {
    _subStream?.cancel();
    var recebeu = false;

    Future<void> finalizar() async {
      if (_modoAudio && _vozParag.trim().isNotEmpty) {
        _enfileirarVoz(_vozParag.trim()); // fala o último parágrafo que faltou
      }
      _vozParag = '';
      final atual = await ChatStore.porId(idOrigem);
      if (!mounted) return;
      setState(() {
        if (atual != null) _conv = atual;
        _enviando = false;
        _streamando = false;
        _streamTexto = '';
        _proxSep = ' ';
      });
      _rolarFim(inicioResposta: true);
    }

    _subStream = stream.listen((e) {
      if (!mounted) return;
      final mesma = _conv.id == idOrigem;
      switch (e.tipo) {
        case 'frase':
          recebeu = true;
          if (mesma) {
            // O bloco [[ACAO:...]] não aparece nem é falado (só executa no fim).
            final limpa = ChatActions.limpar(e.texto);
            if (limpa.isEmpty) break;
            // Texto ao vivo: parágrafos preservados (quebra dupla ao fim de parágrafo).
            setState(() {
              _streamTexto = _streamTexto.isEmpty
                  ? limpa
                  : '$_streamTexto$_proxSep$limpa';
              _proxSep = e.fimParagrafo ? '\n\n' : ' ';
            });
            _rolarFim();
            // Voz por PARÁGRAFO: acumula as frases e fala quando o parágrafo fecha,
            // MAS só se já tiver texto suficiente (~80 chars) — assim uma 1ª linha
            // curta/título NÃO é falada sozinha (ela "secaria" antes do próximo
            // ficar pronto, criando o vão); junta com o próximo numa fala só.
            if (_modoAudio) {
              _vozParag = _vozParag.isEmpty ? limpa : '$_vozParag $limpa';
              if (e.fimParagrafo && _vozParag.trim().length >= 80) {
                _enfileirarVoz(_vozParag.trim());
                _vozParag = '';
              }
            }
          }
        case 'done':
          _tick?.cancel();
          if (mesma) finalizar();
        case 'acao':
          // Confirmação de ação executada (lembrete/nota criados).
          if (mesma) _snack(e.texto);
        case 'erro':
          _tick?.cancel();
          if (!recebeu) {
            _fallbackEnvio(idOrigem, snapshot, imgs); // nada veio: envio normal
          } else if (mesma) {
            finalizar(); // já salvou o parcial; só recarrega
          }
      }
    }, onError: (_) {
      if (!recebeu) _fallbackEnvio(idOrigem, snapshot, imgs);
    });
  }

  /// Caminho de RESERVA (robusto, como antes do streaming): usado se o streaming
  /// falhar sem produzir nada. Sobrevive ao voltar e salva via `anexarIa`.
  Future<void> _fallbackEnvio(
      String idOrigem, List<ChatMessage> snapshot, List<String>? imgs) async {
    if (mounted) {
      setState(() {
        _streamando = false;
        _streamTexto = '';
      });
    }
    // Reatação sem histórico (voltou e o stream morreu na hora): não reenviar vazio.
    if (snapshot.isEmpty) {
      if (mounted) setState(() => _enviando = false);
      return;
    }
    final res = await ChatService.enviarNaConversa(idOrigem, snapshot,
        presetId: _conv.preset.id,
        modeloId: _conv.modelo.id,
        tamanhoId: _conv.tamanho.id,
        imagensB64: imgs);
    _tick?.cancel();
    if (!mounted) return;
    if (_conv.id != idOrigem) {
      if (!res.sucesso) {
        final orig = await ChatStore.porId(idOrigem);
        if (orig != null) {
          orig.mensagens = [...orig.mensagens, ChatMessage.ia('⚠️ ${res.erro}')];
          await ChatStore.salvar(orig);
        }
        if (!mounted) return;
      }
      setState(() => _enviando = ChatService.pendenteDe(_conv.id) != null);
      return;
    }
    if (res.sucesso) {
      final atual = await ChatStore.porId(idOrigem);
      if (!mounted) return;
      setState(() {
        if (atual != null) _conv = atual;
        _enviando = false;
      });
      _rolarFim(inicioResposta: true);
      _autoFalar();
      for (final a in res.acoes) {
        _snack(a);
      }
    } else {
      setState(() {
        _conv.mensagens = [..._conv.mensagens, ChatMessage.ia('⚠️ ${res.erro}')];
        _enviando = false;
      });
      await ChatStore.salvar(_conv);
    }
    _foco.requestFocus();
  }

  Future<void> _novaConversa() async {
    if (!_conv.vazia) await ChatStore.salvar(_conv);
    setState(() => _conv = Conversa.nova(_conv.preset));
    await ChatStore.marcarUltima(_conv.id);
  }

  /// Renomeia uma conversa (usado ao segurar no histórico). O nome aparece no topo.
  Future<void> _renomear(Conversa conv) async {
    final ctrl = TextEditingController(text: conv.titulo);
    final novo = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Renomear conversa'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: 'Nome da conversa'),
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (novo != null && novo.isNotEmpty) {
      conv.titulo = novo;
      await ChatStore.salvar(conv);
      // Reflete no título do topo mesmo sendo outra instância (histórico).
      if (conv.id == _conv.id) _conv.titulo = novo;
      if (mounted) setState(() {});
    }
  }

  Future<void> _abrirHistorico() async {
    if (!_conv.vazia) await ChatStore.salvar(_conv);
    var convs = await ChatStore.listar();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(children: [
                const Expanded(
                  child: Text('Conversas',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Nova'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _novaConversa();
                  },
                ),
              ]),
            ),
            if (convs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhuma conversa ainda.'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: convs.length,
                  itemBuilder: (c, i) {
                    final conv = convs[i];
                    final atual = conv.id == _conv.id;
                    return ListTile(
                      leading: Icon(_icone(conv.preset)),
                      title: Text(conv.titulo,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${conv.preset.rotulo} · ${conv.tamanho.rotulo} · ${_data(conv.atualizadaEm)}'),
                      selected: atual,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Apagar',
                        onPressed: () async {
                          await ChatStore.remover(conv.id);
                          convs = await ChatStore.listar();
                          setSheet(() {});
                          if (atual && mounted) {
                            setState(() => _conv = convs.isNotEmpty
                                ? convs.first
                                : Conversa.nova(_conv.preset));
                          }
                        },
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        setState(() => _conv = conv);
                        await ChatStore.marcarUltima(conv.id);
                        // Abre direto na 1ª linha da última resposta da Muse, SEM
                        // animar a conversa inteira até o fim (instantâneo) — igual
                        // ao reabrir o app (`_carregar`).
                        _abrirNoFim();
                      },
                      // Segurar = renomear (o nome aparece no topo).
                      onLongPress: () async {
                        await _renomear(conv);
                        convs = await ChatStore.listar();
                        setSheet(() {});
                      },
                    );
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }

  PopupMenuItem<String> _item(String v, IconData ic, String t) => PopupMenuItem(
        value: v,
        child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(ic),
            title: Text(t)),
      );

  Future<void> _acaoMenu(String v) async {
    switch (v) {
      case 'nova':
        await _novaConversa();
      case 'resumo':
        _resumir();
      case 'renomear':
        _renomear(_conv);
      case 'relatorio':
        await _mostrarRelatorio();
      case 'devagar':
        setState(() => _conv.falaDevagar = !_conv.falaDevagar);
        await ChatStore.salvar(_conv);
        _snack(_conv.falaDevagar
            ? 'Fala devagar ativada nesta conversa'
            : 'Fala devagar desativada');
      default:
        if (v.startsWith('m_')) {
          setState(() => _conv.modelo = ChatModelo.deId(v.substring(2)));
          await ChatStore.salvar(_conv);
          _snack('Modelo: ${_conv.modelo.rotulo}');
        } else if (v.startsWith('t_')) {
          setState(() => _conv.tamanho = ChatTamanho.deId(v.substring(2)));
          await ChatStore.salvar(_conv);
          _snack(_conv.tamanho == ChatTamanho.curto
              ? 'Respostas curtas (cerca de metade, sem cortar)'
              : 'Respostas longas (tamanho completo)');
        }
    }
  }

  /// Mostra as falhas capturadas (Diagnostico) e deixa ENVIAR (ao proxy do
  /// Muse), COMPARTILHAR (outro canal) ou LIMPAR. Ajuda a diagnosticar
  /// travamentos/erros que o usuário encontrar.
  Future<void> _mostrarRelatorio() async {
    final texto = Diagnostico.texto();
    final vazio = Diagnostico.vazio;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Relatório de erros (${Diagnostico.quantidade})'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(texto,
                style: const TextStyle(fontSize: 12, height: 1.3)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: vazio
                ? null
                : () async {
                    await Diagnostico.limpar();
                    if (ctx.mounted) Navigator.pop(ctx);
                    _snack('Relatório limpo');
                  },
            child: const Text('Limpar'),
          ),
          TextButton(
            onPressed: () => SharePlus.instance.share(ShareParams(
                text: texto, subject: 'Taskix — relatório de erros')),
            child: const Text('Compartilhar'),
          ),
          FilledButton(
            onPressed: vazio
                ? null
                : () async {
                    final ok = await Diagnostico.enviar();
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    _snack(ok
                        ? 'Relatório enviado. Obrigado!'
                        : 'Falha ao enviar — tente Compartilhar.');
                  },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Busca na conversa ─────────────────────────
  void _fecharBusca() {
    setState(() {
      _buscando = false;
      _busca = '';
      _hits = [];
      _hitAtual = -1;
      _buscaCtrl.clear();
    });
  }

  void _atualizarBusca(String termo) {
    final q = termo.trim().toLowerCase();
    final hits = <(int, int)>[];
    if (q.isNotEmpty) {
      for (var i = 0; i < _conv.mensagens.length; i++) {
        final low = _semCarimbo(_conv.mensagens[i].texto).toLowerCase();
        var start = low.indexOf(q);
        while (start >= 0) {
          hits.add((i, start)); // cada OCORRÊNCIA (não cada mensagem)
          start = low.indexOf(q, start + q.length);
        }
      }
    }
    setState(() {
      _busca = termo.trim();
      _hits = hits;
      _hitAtual = hits.isEmpty ? -1 : hits.length - 1; // começa na mais recente
    });
    if (_hitAtual >= 0) _irPara(_hits[_hitAtual].$1);
  }

  void _irHit(int delta) {
    if (_hits.isEmpty) return;
    setState(() => _hitAtual = (_hitAtual + delta) % _hits.length);
    _irPara(_hits[_hitAtual].$1);
  }

  void _irPara(int msgIdx) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.scrollToIndex(msgIdx,
            preferPosition: AutoScrollPosition.middle,
            duration: const Duration(milliseconds: 300));
      }
    });
  }

  List<Widget> _acoesBusca() => [
        Center(
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              _busca.isEmpty
                  ? ''
                  : (_hits.isEmpty ? '0' : '${_hitAtual + 1}/${_hits.length}'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        IconButton(
            icon: const Icon(Icons.keyboard_arrow_up),
            tooltip: 'Anterior',
            onPressed: _hits.isEmpty ? null : () => _irHit(-1)),
        IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            tooltip: 'Próximo',
            onPressed: _hits.isEmpty ? null : () => _irHit(1)),
      ];

  /// Quebra o texto em trechos, grifando as ocorrências; a ocorrência ATUAL
  /// (a que a navegação ▲/▼ aponta) fica em laranja/negrito.
  List<TextSpan> _grifar(String texto, TextStyle base, int msgIdx) {
    if (_busca.isEmpty) return [TextSpan(text: texto, style: base)];
    final spans = <TextSpan>[];
    final low = texto.toLowerCase();
    final q = _busca.toLowerCase();
    final atual = (_hitAtual >= 0 && _hits[_hitAtual].$1 == msgIdx)
        ? _hits[_hitAtual].$2
        : -1;
    var start = 0;
    while (true) {
      final i = low.indexOf(q, start);
      if (i < 0) {
        spans.add(TextSpan(text: texto.substring(start), style: base));
        break;
      }
      if (i > start) {
        spans.add(TextSpan(text: texto.substring(start, i), style: base));
      }
      final ehAtual = i == atual;
      spans.add(TextSpan(
        text: texto.substring(i, i + q.length),
        style: base.copyWith(
            backgroundColor: ehAtual ? Colors.orange : Colors.amber,
            color: Colors.black,
            fontWeight: ehAtual ? FontWeight.bold : null),
      ));
      start = i + q.length;
    }
    return spans;
  }

  /// Pede ao Muse um resumo da conversa (tamanho bom p/ colar em outra IA).
  Future<void> _resumir() async {
    if (_conv.mensagens.isEmpty) {
      _snack('Nada para resumir ainda.');
      return;
    }
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));
    final res = await ChatService.enviar(_conv.mensagens,
        presetId: 'resumo', modeloId: _conv.modelo.id);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // fecha o loading
    final texto = res.sucesso ? res.reply! : '⚠️ ${res.erro}';
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Resumo da conversa'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(texto)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Fechar')),
          if (res.sucesso)
            FilledButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copiar'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: texto));
                Navigator.pop(c);
                _snack('Resumo copiado (cole no ChatGPT)');
              },
            ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  String _data(DateTime d) {
    final dia = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    final hora = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '$dia $hora';
  }

  /// Rótulo de hora de UMA mensagem (embaixo da bolha): hoje = só HH:mm,
  /// ontem = "ontem HH:mm", outros dias = "dd/MM HH:mm". Vazio p/ data inválida
  /// (JSON antigo sem hora).
  String _rotuloHora(DateTime d) {
    if (d.millisecondsSinceEpoch <= 0) return '';
    final hhmm =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final dia = DateTime(d.year, d.month, d.day);
    final diff = hoje.difference(dia).inDays;
    if (diff <= 0) return hhmm;
    if (diff == 1) return 'ontem $hhmm';
    final ddmm =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return '$ddmm $hhmm';
  }

  @override
  Widget build(BuildContext context) {
    final logado = SyncService.instance.conectado;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        // Voltar SEMPRE na cor de acento do tema (terracota), como os demais —
        // no modo busca o mesmo botão fecha a busca.
        leading: _placaTopo(
          tooltip: _buscando ? 'Fechar busca' : 'Voltar',
          onTap: _buscando
              ? _fecharBusca
              : () => Navigator.of(context).maybePop(),
          filho: const Icon(Icons.arrow_back, size: 24),
        ),
        // Nome da conversa (ou campo de busca no modo busca).
        title: _buscando
            ? TextField(
                controller: _buscaCtrl,
                autofocus: true,
                onChanged: _atualizarBusca,
                onSubmitted: (_) => _irHit(1), // Enter = próxima ocorrência
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                    hintText: 'Buscar na conversa…', border: InputBorder.none),
              )
            : Text(
                _conv.titulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, height: 1.1),
              ),
        actions: _buscando
            ? _acoesBusca()
            : [
                _placaTopo(
                  tooltip: 'Buscar na conversa',
                  onTap: _conv.mensagens.isEmpty
                      ? null
                      : () => setState(() => _buscando = true),
                  filho: const Icon(Icons.search, size: 24),
                ),
                // Seletor de MODO (mostra o modo atual).
                _placaTopoMenu<ChatPreset>(
                  tooltip: 'Modo',
                  initialValue: _conv.preset,
                  onSelected: (p) async {
                    setState(() => _conv.preset = p);
                    if (!_conv.vazia) await ChatStore.salvar(_conv);
                  },
                  itemBuilder: (_) => [
                    for (final p in ChatPreset.values)
                      PopupMenuItem(
                        value: p,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(_icone(p)),
                          title: Text(p.rotulo),
                          subtitle: Text(p.descricao),
                        ),
                      ),
                  ],
                  // Só a seta (o modo atual aparece marcado dentro do menu).
                  filho: const Icon(Icons.arrow_drop_down, size: 26),
                ),
                _placaTopo(
                  tooltip: 'Conversas',
                  onTap: _abrirHistorico,
                  filho: const Icon(Icons.history, size: 24),
                ),
                // Menu: nova, resumo, renomear e MODELO de IA.
                _placaTopoMenu<String>(
                  tooltip: 'Mais',
                  onSelected: _acaoMenu,
                  itemBuilder: (_) => [
              _item('nova', Icons.add_comment_outlined, 'Nova conversa'),
              _item('resumo', Icons.summarize_outlined, 'Resumo da conversa'),
              _item('renomear', Icons.edit_outlined, 'Renomear conversa'),
              _item('relatorio', Icons.bug_report_outlined, 'Relatório de erros'),
              const PopupMenuDivider(),
              for (final mdl in ChatModelo.values)
                PopupMenuItem(
                  value: 'm_${mdl.id}',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_conv.modelo == mdl
                        ? Icons.check
                        : Icons.smart_toy_outlined),
                    title: Text('Modelo: ${mdl.rotulo}'),
                    subtitle: Text(mdl.descricao),
                  ),
                ),
              const PopupMenuDivider(),
              // Tamanho da resposta (vale a partir da próxima mensagem). Curto
              // nunca corta: o servidor ainda obriga concluir o raciocínio e
              // terminar as frases, mantendo o tom motivador/propositivo.
              for (final tam in ChatTamanho.values)
                PopupMenuItem(
                  value: 't_${tam.id}',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_conv.tamanho == tam
                        ? Icons.check
                        : Icons.straighten),
                    title: Text('Tamanho: ${tam.rotulo}'),
                    subtitle: Text(tam.descricao),
                  ),
                ),
              const PopupMenuDivider(),
              // Fala devagar SÓ nesta conversa (soma ao ritmo das Configurações).
              PopupMenuItem(
                value: 'devagar',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_conv.falaDevagar
                      ? Icons.check
                      : Icons.speed_outlined),
                  title: const Text('Fala devagar'),
                  subtitle: const Text('Respostas faladas mais devagar (só aqui)'),
                ),
              ),
            ],
                  filho: const Icon(Icons.more_vert, size: 24),
                ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : logado
              ? _conversa(context)
              : _conviteLogin(context),
    );
  }

  /// Botão GHOST do topo do chat (sem caixa): só o desenho, na cor de ACENTO do
  /// tema (terracota no Terracota) — diferente do home/projeto, que usam branco.
  /// `filho` usa a cor do `IconTheme` (não fixe cor nos Icons).
  Widget _placaTopo({
    required String tooltip,
    required VoidCallback? onTap,
    required Widget filho,
    double largura = 40,
  }) {
    final cor =
        (Theme.of(context).extension<AppCores>() ?? AppCores.azul).fab;
    final tile = Container(
      width: largura,
      height: 40,
      alignment: Alignment.center,
      child: IconTheme(
        data: const IconThemeData(size: 24).copyWith(color: cor),
        child: filho,
      ),
    );
    if (onTap == null) {
      return Opacity(
          opacity: 0.45, child: Tooltip(message: tooltip, child: tile));
    }
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: tile,
        ),
      ),
    );
  }

  /// Variante da plaquinha para botões de menu (Modo ⋮ / Mais ⋮): o próprio
  /// `PopupMenuButton` desenha a plaquinha como fundo (via `child`), mantendo
  /// o ripple e o comportamento de menu. Sem ela o `icon:` padrão forçaria um
  /// IconButton de 48px que estouraria a plaquinha de 34px.
  Widget _placaTopoMenu<T>({
    required String tooltip,
    required void Function(T) onSelected,
    required List<PopupMenuEntry<T>> Function(BuildContext) itemBuilder,
    required Widget filho,
    T? initialValue,
    double largura = 40,
  }) {
    final cor =
        (Theme.of(context).extension<AppCores>() ?? AppCores.azul).fab;
    return Tooltip(
      message: tooltip,
      child: Container(
        width: largura,
        height: 40,
        alignment: Alignment.center,
        child: IconTheme(
          data: const IconThemeData(size: 24).copyWith(color: cor),
          child: PopupMenuButton<T>(
            tooltip: tooltip,
            padding: EdgeInsets.zero,
            initialValue: initialValue,
            onSelected: onSelected,
            itemBuilder: itemBuilder,
            child: filho,
          ),
        ),
      ),
    );
  }

  Widget _conviteLogin(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline,
              size: 54, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text(
            'Entre com sua conta Google para usar a Muse Spark.\n'
            'Só a sua conta tem acesso — ninguém mais usa seus créditos.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.login),
            label: const Text('Entrar com Google'),
            onPressed: () => SyncService.instance.entrarComGoogle(),
          ),
        ]),
      ),
    );
  }

  Widget _conversa(BuildContext context) {
    return Column(children: [
      Container(
        width: double.infinity,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          'Modo ${_conv.preset.rotulo} • ${_conv.tamanho.rotulo} • ${_conv.modelo.rotulo}${_conv.falaDevagar ? ' • Devagar' : ''}',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary),
        ),
      ),
      Expanded(
        child: _conv.vazia
            ? _vazio(context)
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                itemCount: _conv.mensagens.length + (_enviando ? 1 : 0),
                itemBuilder: (c, i) {
                  // O "pensando" tem tag própria (índice n) p/ o _rolarFim mirar nele
                  // durante o envio — sem isso o scroll parava na msg enviada e o
                  // contador ficava escondido embaixo.
                  if (i == _conv.mensagens.length) {
                    // Durante o streaming, mostra a resposta chegando AO VIVO; antes
                    // da 1ª frase, o "pensando…" com o contador.
                    return AutoScrollTag(
                      key: const ValueKey('pensando'),
                      controller: _scroll,
                      index: i,
                      child: (_streamando && _streamTexto.isNotEmpty)
                          ? _bolhaStream(context)
                          : _pensando(context),
                    );
                  }
                  // AutoScrollTag permite pular até a mensagem na busca.
                  return AutoScrollTag(
                    key: ValueKey('msg_$i'),
                    controller: _scroll,
                    index: i,
                    child: _bolha(context, _conv.mensagens[i], i),
                  );
                },
              ),
      ),
      _barraEntrada(context),
    ]);
  }

  Widget _vazio(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            _conv.preset == ChatPreset.coach
                ? 'Peça uma análise do seu treino, ou diga "oi" que a Muse Spark te dá o panorama.'
                : 'Mande uma mensagem para começar a discutir seus projetos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
        ),
      );

  Widget _bolha(BuildContext context, ChatMessage m, int idx) {
    final cs = Theme.of(context).colorScheme;
    final ehEu = m.ehUsuario;
    final estilo =
        TextStyle(color: ehEu ? cs.onPrimary : cs.onSurface, height: 1.3);
    // Texto SEM o carimbo de data/hora (some da escrita; só o servidor usa p/
    // contexto). Na busca, grifa as ocorrências; senão texto simples.
    final txt = _semCarimbo(m.texto);
    final texto = _busca.isEmpty
        ? Text(txt, style: estilo)
        : Text.rich(TextSpan(children: _grifar(txt, estilo, idx)));
    final hora = _rotuloHora(m.hora);
    return Align(
      alignment: ehEu ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            ehEu ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Segurar = menu com Copiar / Salvar no Estudos (mensagem INTEIRA, sem
          // precisar selecionar tudo).
          GestureDetector(
            onLongPress: () => _acoesMensagem(m, idx),
            child: Container(
              margin: const EdgeInsets.only(top: 4, bottom: 2),
              padding:
                  EdgeInsets.fromLTRB(14, 10, ehEu ? 14 : 6, ehEu ? 10 : 2),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.82),
              decoration: BoxDecoration(
                color: ehEu ? cs.primary : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(ehEu ? 16 : 4),
                  bottomRight: Radius.circular(ehEu ? 4 : 16),
                ),
              ),
              // Resposta da IA: botãozinho de ÁUDIO no canto inferior direito (cabe
              // dentro da bolha, sem alargá-la).
              child: ehEu
                  ? texto
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: texto),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Recomeçar a leitura do INÍCIO desta mensagem.
                              InkWell(
                                onTap: () => _recomecarFala(idx, m.texto),
                                customBorder: const CircleBorder(),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Icon(Icons.replay,
                                      size: 24, color: cs.onSurfaceVariant),
                                ),
                              ),
                              // Alto-falante: tocar = play/pausa; segurar = parar.
                              InkWell(
                                onTap: () => _falar(idx, m.texto),
                                onLongPress: () => _pararReplay(),
                                customBorder: const CircleBorder(),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Icon(
                                    _lendoIdx == idx
                                        ? (_gerandoVoz
                                            ? Icons.hourglass_bottom_outlined
                                            : (_pausado
                                                ? Icons.play_circle_outline
                                                : Icons.pause_circle_outline))
                                        : Icons.volume_up_outlined,
                                    size: 26,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          // Data/hora FORA e EMBAIXO da bolha (não vai no Copiar).
          if (hora.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                  left: ehEu ? 0 : 4, right: ehEu ? 4 : 0, bottom: 4),
              child: Text(hora,
                  style: TextStyle(
                      fontSize: 11, color: Theme.of(context).hintColor)),
            ),
        ],
      ),
    );
  }

  void _copiar(String texto) {
    Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Mensagem copiada'),
        duration: Duration(seconds: 1),
      ));
  }

  /// Menu ao segurar uma mensagem: copiar ou mandar para o projeto "Estudos".
  Future<void> _acoesMensagem(ChatMessage m, int idx) async {
    // Tira o foco da caixa ANTES de abrir o menu: senão, ao fechar o bottom
    // sheet (ex.: depois de Copiar), o foco voltava p/ o campo e o teclado
    // reabria sozinho. O "Editar" refoca de propósito depois (em _editarMensagem).
    FocusScope.of(context).unfocus();
    final texto = _semCarimbo(m.texto);
    final msgs = _conv.mensagens;
    final ehUltima = idx == msgs.length - 1;
    final ultimoUserIdx = msgs.lastIndexWhere((x) => x.ehUsuario);
    // Tentar de novo: regenera a ÚLTIMA resposta da Muse. Editar: corrige a sua
    // ÚLTIMA mensagem e reenvia. Ambos só fora de um envio em andamento.
    final podeRegenerar = ehUltima && !m.ehUsuario && !_enviando;
    final podeEditar = m.ehUsuario && idx == ultimoUserIdx && !_enviando;
    final escolha = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (podeRegenerar)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Tentar de novo'),
                subtitle: const Text('Gera outra resposta para a mesma pergunta'),
                onTap: () => Navigator.pop(ctx, 'regenerar'),
              ),
            if (podeEditar)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Editar e reenviar'),
                subtitle: const Text('Corrige o que você enviou, sem reescrever tudo'),
                onTap: () => Navigator.pop(ctx, 'editar'),
              ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copiar'),
              onTap: () => Navigator.pop(ctx, 'copiar'),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Salvar no Estudos'),
              onTap: () => Navigator.pop(ctx, 'estudos'),
            ),
          ],
        ),
      ),
    );
    if (escolha == 'copiar') {
      _copiar(texto);
    } else if (escolha == 'estudos') {
      await _salvarNoEstudos(texto);
    } else if (escolha == 'regenerar') {
      await _regenerar();
    } else if (escolha == 'editar') {
      await _editarMensagem(idx);
    }
  }

  /// TENTAR DE NOVO: remove a última resposta da Muse e pede OUTRA para a mesma
  /// pergunta (a resposta antiga sai do histórico → a Muse gera do zero; com a
  /// variação natural da persona + temperatura, não repete a resposta anterior).
  Future<void> _regenerar() async {
    if (_enviando) return;
    final msgs = _conv.mensagens;
    if (msgs.isEmpty || msgs.last.ehUsuario) return; // precisa de uma resposta no fim
    await _pararFala();
    setState(() {
      _conv.mensagens = msgs.sublist(0, msgs.length - 1); // tira a resposta antiga
      _enviando = true;
      _streamando = true;
      _streamTexto = '';
      _proxSep = ' ';
      _vozParag = '';
      _inicioEnvio = DateTime.now();
    });
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
    await ChatStore.salvar(_conv);
    await ChatStore.marcarUltima(_conv.id);
    _rolarFim();
    final idOrigem = _conv.id;
    final snapshot = List<ChatMessage>.from(_conv.mensagens);
    _escutarStream(
      idOrigem,
      ChatService.enviarStream(idOrigem, snapshot,
          presetId: _conv.preset.id,
          modeloId: _conv.modelo.id,
          tamanhoId: _conv.tamanho.id),
      snapshot,
      null,
    );
  }

  /// EDITAR E REENVIAR: devolve o texto da sua última mensagem para a caixa (sem
  /// os carimbos de anexo/imagem) e remove a mensagem + o que veio depois. Você
  /// corrige e toca em enviar → a Muse responde à versão corrigida.
  Future<void> _editarMensagem(int idx) async {
    if (_enviando) return;
    final msgs = _conv.mensagens;
    if (idx < 0 || idx >= msgs.length || !msgs[idx].ehUsuario) return;
    await _pararFala();
    var t = msgs[idx].texto;
    final iAnexo = t.indexOf('\n\n--- Anexo ---');
    if (iAnexo >= 0) t = t.substring(0, iAnexo);
    t = t.replaceAll(RegExp(r'\n?\[📷[^\]]*\]'), '').trimRight();
    setState(() {
      _conv.mensagens = msgs.sublist(0, idx); // tira a sua msg e tudo depois
      _ctrl.text = t;
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    });
    await ChatStore.salvar(_conv);
    _foco.requestFocus();
    _snack('Edite a mensagem e toque em enviar para reenviar.');
  }

  /// Guarda a mensagem como uma caixinha no projeto reservado "Estudos" (cria se
  /// não existir) — é lá que o usuário acumula trechos da Muse / resumos.
  Future<void> _salvarNoEstudos(String texto) async {
    await Storage.instance.adicionarNotaEmProjeto('Estudos', texto);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Salvo no Estudos'),
        duration: Duration(seconds: 1),
      ));
  }

  Widget _pensando(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('pensando… ${_tempoEspera()}s',
                style: TextStyle(color: Theme.of(context).hintColor)),
          ]),
        ),
      );

  /// Balão da resposta chegando AO VIVO (streaming): mesmo estilo da bolha da IA,
  /// com um cursorzinho piscando no fim p/ indicar que ainda está escrevendo.
  Widget _bolhaStream(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 2),
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Text('${_semCarimbo(_streamTexto)} ▌',
            style: TextStyle(color: cs.onSurface, height: 1.3)),
      ),
    );
  }

  /// Segundos.décimos desde o envio (ex.: "2.3").
  String _tempoEspera() {
    final ms = _inicioEnvio == null
        ? 0
        : DateTime.now().difference(_inicioEnvio!).inMilliseconds;
    return (ms / 1000).toStringAsFixed(1);
  }

  // ───────────────────────── Anexo (clip) ─────────────────────────
  Future<void> _anexar() async {
    final escolha = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.content_paste),
            title: const Text('Colar / escrever um texto'),
            subtitle: const Text('Ex.: um texto copiado da internet'),
            onTap: () => Navigator.pop(c, 'texto'),
          ),
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: const Text('Anexar arquivo de texto'),
            subtitle: const Text('.txt, .md, .csv…'),
            onTap: () => Navigator.pop(c, 'arquivo'),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Anexar imagens (até 3)'),
            subtitle: const Text('A Muse Spark analisa as fotos (visão)'),
            onTap: () => Navigator.pop(c, 'imagem'),
          ),
        ]),
      ),
    );
    if (escolha == 'texto') await _anexarTexto();
    if (escolha == 'arquivo') await _anexarArquivo();
    if (escolha == 'imagem') await _anexarImagem();
  }

  Future<void> _anexarImagem() async {
    try {
      if (_imagensB64.length >= _maxImagens) {
        _snack('Máximo de $_maxImagens imagens por mensagem');
        return;
      }
      final xs = await ImagePicker().pickMultiImage(
          maxWidth: 1280, imageQuality: 70);
      if (xs.isEmpty) return;
      final faltam = _maxImagens - _imagensB64.length;
      var avisou = false;
      for (final x in xs.take(faltam)) {
        final bytes = await x.readAsBytes();
        _imagensB64.add(base64Encode(bytes));
      }
      if (xs.length > faltam) avisou = true;
      if (mounted) {
        setState(() {});
        if (avisou) _snack('Só as $_maxImagens primeiras foram anexadas');
      }
    } catch (_) {}
  }

  Future<void> _anexarTexto() async {
    final ctrl = TextEditingController(text: _anexo ?? '');
    final t = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Anexar texto'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          decoration:
              const InputDecoration(hintText: 'Cole aqui o texto para a Muse Spark analisar…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: const Text('Anexar')),
        ],
      ),
    );
    if (t != null) setState(() => _anexo = t.isEmpty ? null : t);
  }

  Future<void> _anexarArquivo() async {
    try {
      final res = await FilePicker.platform.pickFiles(withData: true);
      if (res == null || res.files.isEmpty) return;
      final arq = res.files.first;
      final bytes = arq.bytes;
      if (bytes == null) return;
      var txt = '';
      try {
        txt = utf8.decode(bytes);
      } catch (_) {
        txt = String.fromCharCodes(bytes);
      }
      if (txt.length > 20000) txt = '${txt.substring(0, 20000)}\n…(cortado)';
      setState(() => _anexo = '[arquivo: ${arq.name}]\n$txt');
    } catch (_) {}
  }

  Widget _barraEntrada(BuildContext context) {
    // Botão de ENVIAR em DEGRADÊ, derivado do acento do tema (terracota no
    // Terracota; cada tema usa o seu `fab`/`fabIcone`).
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.azul;
    final sendG1 = Color.lerp(app.fab, Colors.white, 0.20)!;
    final sendG2 = Color.lerp(app.fab, Colors.black, 0.28)!;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 10, 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_anexo != null || _imagensB64.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Wrap(spacing: 6, children: [
                  if (_anexo != null)
                    Chip(
                      avatar: const Icon(Icons.attach_file, size: 16),
                      label: Text('Anexo (${_anexo!.length} caracteres)'),
                      onDeleted: () => setState(() => _anexo = null),
                    ),
                  for (var i = 0; i < _imagensB64.length; i++)
                    Chip(
                      avatar: const Icon(Icons.image, size: 16),
                      label: Text(_imagensB64.length == 1
                          ? 'Imagem anexada'
                          : 'Imagem ${i + 1}'),
                      onDeleted: () => setState(() => _imagensB64.removeAt(i)),
                    ),
                ]),
              ),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              // Barra de rolagem sempre visível (estilo WhatsApp): mostra que há
              // mais texto acima quando passa do limite, cortando pelo topo.
              child: Scrollbar(
                controller: _caixaScroll,
                thumbVisibility: true,
                thickness: 4,
                radius: const Radius.circular(4),
                child: TextField(
                controller: _ctrl,
                focusNode: _foco,
                scrollController: _caixaScroll,
                // Altura inicial acompanha a coluna da direita (anexo + enviar):
                // 3 linhas ≈ mesma altura total dos dois botões empilhados.
                // Teto de 10 linhas como no WhatsApp (corta pelo topo e rola).
                minLines: 3,
                maxLines: 10,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.newline,
                onTap: () {
                  // Gravando: tocar na caixa PARA a gravação mantendo o texto
                  // (equivale ao antigo X lateral, sem comer largura da caixa).
                  if (_gravando && !_enviando) _micCancel();
                  _rolarFim();
                  // NÃO rola a caixa p/ o fim aqui: o toque posiciona o cursor
                  // e o próprio campo o revela; forçar o fim escondia o trecho
                  // tocado em mensagem longa.
                },
                // Digitando a caixa cresce (1→5 linhas) e o teclado pode cobrir o
                // fim: mantém a última mensagem visível + o fim do texto da caixa
                // SÓ quando o cursor está no fim (digitando/ditando no fim).
                // Editando no meio do texto, forçar o fim escondia o trecho.
                onChanged: (_) {
                  _rolarFim(instantaneo: true);
                  if (_ctrl.selection.extentOffset >= _ctrl.text.length) {
                    _rolarCaixaFim();
                  }
                },
                decoration: InputDecoration(
                  hintText: _gravando
                      ? 'Ouvindo… toque aqui p/ parar ou no enviar p/ concluir'
                      : 'Escreva sua mensagem…',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  // X p/ limpar o que está escrito/ditado (texto + anexo + imagens).
                  // ValueListenable mostra/esconde sem setState a cada tecla.
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _ctrl,
                    builder: (context, v, child) {
                      final temAlgo = v.text.isNotEmpty ||
                          _anexo != null ||
                          _imagensB64.isNotEmpty;
                      if (!temAlgo) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: 'Limpar',
                        onPressed: _enviando ? null : _limparCaixa,
                      );
                    },
                  ),
                ),
                ),
              ),
            ),
            // Coluna da direita: ANEXO (pequeno) em cima + ENVIAR (grande) embaixo.
            //  • TOQUE no enviar = envia o texto digitado (não fala a resposta).
            //  • SEGURAR o enviar = inicia e TRAVA a gravação (vermelho); soltar
            //    NÃO para. Com gravando: TOQUE no enviar conclui e envia (voz→voz);
            //    TOQUE na caixa para a gravação mantendo o texto (sem X lateral,
            //    p/ não estreitar a caixa). A Row é ancorada embaixo (end) p/ a caixa
            //    crescer para cima sem deslocar o botão de baixo do dedo.
            // O toque vai no FAB.onPressed; o segurar, no GestureDetector.
            // ⚠️ NÃO pôr tooltip no FAB: o Tooltip consome o long-press p/ exibir
            // o balão e o onLongPressStart nunca dispara (bug da V0.1.137).
            const SizedBox(width: 6),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.attach_file,
                      size: 20,
                      color: (_anexo != null || _imagensB64.isNotEmpty)
                          ? Theme.of(context).colorScheme.primary
                          : null),
                  tooltip: 'Anexar',
                  padding: const EdgeInsets.all(6),
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  splashRadius: 16,
                  onPressed:
                      (_enviando || _gravando) ? null : () => _anexar(),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onLongPressStart: (_) => _micStart(),
                  // Travado de propósito: soltar/cancelar o gesto NÃO encerra.
                  onLongPressEnd: (_) {},
                  onLongPressCancel: () {},
                  // Botão redondo em DEGRADÊ (gravando = vermelho sólido).
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    elevation: 2,
                    child: Ink(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _gravando
                            ? null
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [sendG1, sendG2]),
                        color: _gravando ? Colors.red : null,
                      ),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _enviando
                            ? null
                            : () {
                                if (_gravando) {
                                  _micStop(); // conclui a gravação travada e envia
                                } else {
                                  _modoAudio = false; // digitou → resposta em texto
                                  _enviar();
                                }
                              },
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: Icon(
                            _enviando
                                ? Icons.hourglass_empty
                                : (_gravando ? Icons.mic : Icons.send),
                            size: 28,
                            color: _gravando ? Colors.white : app.fabIcone,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ]),
        ]),
      ),
    );
  }
}
