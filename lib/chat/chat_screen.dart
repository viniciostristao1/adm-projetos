import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../storage.dart';
import '../sync_service.dart';
import 'chat_models.dart';
import 'chat_service.dart';
import 'chat_store.dart';

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
  final _buscaCtrl = TextEditingController();
  bool _buscando = false; // modo busca na conversa
  String _busca = '';
  List<(int, int)> _hits = []; // ocorrências: (índice da mensagem, posição no texto)
  int _hitAtual = -1;
  Conversa _conv = Conversa.nova(ChatPreset.coach);
  bool _enviando = false;
  bool _carregando = true;
  Timer? _tick; // atualiza o contador do "pensando"
  DateTime? _inicioEnvio;
  String? _anexo; // texto anexado (clip) p/ a próxima mensagem
  final List<String> _imagensB64 = []; // imagens anexadas (visão), máx. 3
  static const int _maxImagens = 3;
  final FlutterTts _tts = FlutterTts();
  int? _lendoIdx; // índice da mensagem que está sendo lida (TTS)
  final AudioPlayer _vozNeural = AudioPlayer(); // MP3 da voz neural (/tts)
  bool _gerandoVoz = false; // buscando o áudio (mostra ampulheta)
  // MODO ÁUDIO (segurar o botão enviar): a resposta da Muse toca sozinha, sem
  // tocar no alto-falante — semi-conversação (você dita no Gboard, ela responde
  // em texto + voz). Fica salvo só em memória (default desligado a cada abertura).
  bool _modoAudio = false;
  // Token p/ cancelar/validar a reprodução por frases (streaming): cada nova fala
  // incrementa; loops antigos param ao ver o token mudar.
  int _falaToken = 0;

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
      if (mounted) setState(() => _lendoIdx = null);
    });
    // A conclusão da voz neural é gerida pelo streaming em `_falar` (o listener
    // global zerava o _lendoIdx no fim de CADA frase, cortando a leitura).
    _carregar();
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
  Future<void> _pararFala() async {
    _falaToken++; // invalida o loop de frases em andamento
    await _tts.stop();
    await _vozNeural.stop();
  }

  /// Quebra o texto em FRASES (corta após . ! ? seguido de espaço) p/ tocar
  /// progressivamente — começa a falar a 1ª frase sem esperar o resto. Não corta
  /// decimais (ex.: "3.5") porque exige espaço após a pontuação.
  List<String> _dividirFrases(String t) => t
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// Remove carimbo de data/hora que possa ter vazado no INÍCIO de mensagens
  /// (ex.: "[hoje 23:16] [16/10 …] Oi…"). Novas respostas já vêm limpas do
  /// servidor; isto cobre as ANTIGAS ao falar. Preserva "[📷 imagem]" etc.
  String _semCarimbo(String t) => t.replaceFirst(
      RegExp(r'^\s*(?:\[(?:hoje|ontem|\d{1,2}/\d{1,2})[^\]]*\]\s*)+',
          caseSensitive: false),
      '');

  /// Lê (ou para) a resposta da Muse em voz alta. Toca FRASE A FRASE: busca a 1ª
  /// no /tts e já reproduz (início rápido), enquanto prefetcha a próxima durante a
  /// reprodução — como o Piper é ~5× mais rápido que o tempo real, não há buraco
  /// entre frases. Cai para o TTS do aparelho se a voz neural falhar.
  Future<void> _falar(int idx, String texto) async {
    // Tocar na mesma mensagem que já está lendo = parar (toggle).
    if (_lendoIdx == idx) {
      await _pararFala();
      if (mounted) {
        setState(() {
          _lendoIdx = null;
          _gerandoVoz = false;
        });
      }
      return;
    }
    await _pararFala();
    final token = _falaToken;
    if (mounted) {
      setState(() {
        _lendoIdx = idx;
        _gerandoVoz = true; // buscando a 1ª frase
      });
    }
    final frases = _dividirFrases(_semCarimbo(texto));
    if (frases.isEmpty) {
      if (mounted) {
        setState(() {
          _lendoIdx = null;
          _gerandoVoz = false;
        });
      }
      return;
    }
    // Prefetch com cache: mantém 1 frase à frente (busca enquanto toca a atual).
    final cache = <int, Future<Uint8List?>>{};
    Future<Uint8List?> buscar(int i) =>
        cache.putIfAbsent(i, () => ChatService.audioNeural(frases[i]));
    buscar(0);
    for (var i = 0; i < frases.length; i++) {
      if (token != _falaToken || !mounted) return; // cancelado
      final bytes = await buscar(i);
      if (token != _falaToken || !mounted) return;
      if (i == 0 && mounted) setState(() => _gerandoVoz = false);
      if (i + 1 < frases.length) buscar(i + 1); // prefetcha a próxima
      if (bytes == null) {
        // Neural falhou nesta frase: usa o TTS do aparelho p/ o resto e encerra.
        await _tts.speak(frases.sublist(i).join(' '));
        return;
      }
      final done = Completer<void>();
      final sub = _vozNeural.onPlayerComplete.listen((_) {
        if (!done.isCompleted) done.complete();
      });
      try {
        await _vozNeural.play(BytesSource(bytes));
        while (!done.isCompleted) {
          if (token != _falaToken || !mounted) return; // parou no meio
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } finally {
        await sub.cancel();
      }
    }
    if (token == _falaToken && mounted) {
      setState(() {
        _lendoIdx = null;
        _gerandoVoz = false;
      });
    }
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
    // Se há um envio em voo p/ esta conversa (perguntou e saiu com voltar no
    // meio), reanexa: mostra o "pensando" e aplica a resposta ao chegar.
    final pend = ChatService.pendenteDe(_conv.id);
    if (pend != null) await _reatachar(pend);
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
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SyncService.instance.removeListener(_aoMudarAuth);
    _tick?.cancel();
    _tts.stop();
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
    _foco.dispose();
    super.dispose();
  }

  void _aoMudarAuth() {
    if (mounted) setState(() {});
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
    setState(() {
      _conv.mensagens = [..._conv.mensagens, ChatMessage.usuario(conteudo)];
      _conv.talvezTitular();
      _enviando = true;
      _inicioEnvio = DateTime.now();
      _anexo = null;
      _imagensB64.clear();
    });
    // Conta o tempo de espera (segundos.décimos), atualizando a cada 100ms.
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
    await ChatStore.salvar(_conv);
    await ChatStore.marcarUltima(_conv.id);
    _rolarFim();

    // Envio em BACKGROUND (sobrevive ao botão voltar): o futuro fica registrado
    // por conversa (`ChatService.enviarNaConversa`) e a resposta é salva no store
    // ao concluir — mesmo sem tela montada. Aqui só espelhamos na tela.
    final idOrigem = _conv.id;
    final fut = ChatService.enviarNaConversa(
        idOrigem, List<ChatMessage>.from(_conv.mensagens),
        presetId: _conv.preset.id,
        modeloId: _conv.modelo.id,
        tamanhoId: _conv.tamanho.id,
        imagensB64: imgs.isEmpty ? null : imgs);
    final res = await fut;
    _tick?.cancel();
    if (!mounted) return; // saiu com voltar: o background já salvou a resposta
    if (_conv.id != idOrigem) {
      // Trocou de conversa no meio do envio: a resposta já está salva na origem.
      // Se FALHOU, registra o erro lá (não some em silêncio).
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
      // Recarrega do store (fonte da verdade — o background já anexou lá).
      final atual = await ChatStore.porId(idOrigem);
      if (!mounted) return;
      setState(() {
        if (atual != null) _conv = atual;
        _enviando = false;
      });
      // Resposta chegou: mostra a 1ª linha dela (p/ começar lendo de cima).
      _rolarFim(inicioResposta: true);
      _autoFalar(); // modo áudio: lê a resposta automaticamente
    } else {
      setState(() {
        _conv.mensagens = [
          ..._conv.mensagens,
          ChatMessage.ia('⚠️ ${res.erro}'),
        ];
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
        final low = _conv.mensagens[i].texto.toLowerCase();
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
        leading: _buscando
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Fechar busca',
                onPressed: _fecharBusca)
            : null,
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
                IconButton(
                  tooltip: 'Buscar na conversa',
                  icon: const Icon(Icons.search),
                  onPressed: _conv.mensagens.isEmpty
                      ? null
                      : () => setState(() => _buscando = true),
                ),
                // Seletor de MODO (mostra o modo atual).
          PopupMenuButton<ChatPreset>(
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
            icon: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_icone(_conv.preset)),
              const Icon(Icons.arrow_drop_down),
            ]),
          ),
          IconButton(
            tooltip: 'Conversas',
            icon: const Icon(Icons.history),
            onPressed: _abrirHistorico,
          ),
          // Menu: nova, resumo, renomear e MODELO de IA.
          PopupMenuButton<String>(
            tooltip: 'Mais',
            onSelected: _acaoMenu,
            itemBuilder: (_) => [
              _item('nova', Icons.add_comment_outlined, 'Nova conversa'),
              _item('resumo', Icons.summarize_outlined, 'Resumo da conversa'),
              _item('renomear', Icons.edit_outlined, 'Renomear conversa'),
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
            ],
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
          'Modo ${_conv.preset.rotulo} • ${_conv.tamanho.rotulo}',
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
                    return AutoScrollTag(
                      key: const ValueKey('pensando'),
                      controller: _scroll,
                      index: i,
                      child: _pensando(context),
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
    // Na busca, grifa as ocorrências do termo; senão texto simples.
    final texto = _busca.isEmpty
        ? Text(m.texto, style: estilo)
        : Text.rich(TextSpan(children: _grifar(m.texto, estilo, idx)));
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
            onLongPress: () => _acoesMensagem(m.texto),
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
                          child: InkWell(
                            onTap: () => _falar(idx, m.texto),
                            customBorder: const CircleBorder(),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                _lendoIdx == idx
                                    ? (_gerandoVoz
                                        ? Icons.hourglass_bottom_outlined
                                        : Icons.stop_circle_outlined)
                                    : Icons.volume_up_outlined,
                                size: 18,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
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
  Future<void> _acoesMensagem(String texto) async {
    final escolha = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
    }
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
          Row(children: [
            IconButton(
              icon: Icon(Icons.attach_file,
                  color: (_anexo != null || _imagensB64.isNotEmpty)
                      ? Theme.of(context).colorScheme.primary
                      : null),
              tooltip: 'Anexar',
              onPressed: _anexar,
            ),
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: _foco,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Escreva sua mensagem…',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Segurar o botão ALTERNA o "modo áudio": a resposta da Muse toca
            // sozinha (semi-conversação). No modo áudio o ícone vira microfone e
            // o botão fica destacado. Tocar = enviar (como sempre).
            // NÃO usar `tooltip:` no FAB: o Tooltip do Material captura o
            // long-press (só aparecia a dica, o modo não alternava). Sem ele, o
            // GestureDetector abaixo recebe o onLongPress.
            GestureDetector(
              onLongPress: () {
                setState(() => _modoAudio = !_modoAudio);
                if (!_modoAudio) _pararFala();
                _snack(_modoAudio
                    ? '🎤 Modo áudio LIGADO: a Muse responde falando (dite pelo teclado por voz)'
                    : 'Modo áudio desligado');
              },
              child: FloatingActionButton.small(
                heroTag: 'fab_chat_enviar',
                onPressed: _enviando ? null : _enviar,
                backgroundColor: _modoAudio
                    ? Theme.of(context).colorScheme.tertiary
                    : null,
                foregroundColor: _modoAudio
                    ? Theme.of(context).colorScheme.onTertiary
                    : null,
                child: Icon(_enviando
                    ? Icons.hourglass_empty
                    : (_modoAudio ? Icons.mic : Icons.send)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
