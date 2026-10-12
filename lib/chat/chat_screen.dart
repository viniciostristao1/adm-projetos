import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

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

class _ChatScreenState extends State<ChatScreen> {
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
  String? _imagemB64; // imagem anexada (visão) p/ a próxima mensagem
  final FlutterTts _tts = FlutterTts();
  int? _lendoIdx; // índice da mensagem que está sendo lida (TTS)
  final AudioPlayer _vozNeural = AudioPlayer(); // MP3 da voz neural (/tts)
  bool _gerandoVoz = false; // buscando o áudio (mostra ampulheta)

  /// Ícone de cada modo.
  static IconData _icone(ChatPreset p) => switch (p) {
        ChatPreset.coach => Icons.fitness_center,
        ChatPreset.projetos => Icons.folder_outlined,
        ChatPreset.geral => Icons.forum_outlined,
      };

  @override
  void initState() {
    super.initState();
    SyncService.instance.addListener(_aoMudarAuth);
    _configTts();
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _lendoIdx = null);
    });
    _vozNeural.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _lendoIdx = null);
    });
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

  /// Lê (ou para) a resposta do Muse em voz alta: tenta primeiro a voz neural
  /// pt-BR da VPS (/tts, feminina) e, se falhar, cai para o TTS do aparelho.
  Future<void> _falar(int idx, String texto) async {
    await _tts.stop();
    await _vozNeural.stop();
    if (_lendoIdx == idx) {
      setState(() {
        _lendoIdx = null;
        _gerandoVoz = false;
      });
      return;
    }
    setState(() {
      _lendoIdx = idx;
      _gerandoVoz = true; // buscando o áudio (alguns segundos, sem custo)
    });
    final bytes = await ChatService.audioNeural(texto);
    if (!mounted) return;
    if (bytes != null) {
      setState(() => _gerandoVoz = false);
      try {
        await _vozNeural.play(BytesSource(bytes));
        return;
      } catch (_) {
        // cai para o TTS local abaixo
      }
    }
    setState(() => _gerandoVoz = false);
    await _tts.speak(texto);
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
    _rolarFim();
  }

  @override
  void dispose() {
    SyncService.instance.removeListener(_aoMudarAuth);
    _tick?.cancel();
    _tts.stop();
    _vozNeural.dispose();
    _buscaCtrl.dispose();
    // Ao sair, salva a conversa atual e marca como a última (reabre nela depois).
    if (!_conv.vazia) {
      ChatStore.salvar(_conv);
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
  // inclusive ao abrir, resolvendo o "abriu na penúltima").
  void _rolarFim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final n = _conv.mensagens.length;
      if (n > 0 && _scroll.hasClients) {
        _scroll.scrollToIndex(n - 1,
            preferPosition: AutoScrollPosition.end,
            duration: const Duration(milliseconds: 250));
      }
    });
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    final texto = capitalizarFrases(_ctrl.text.trim());
    final img = _imagemB64;
    if (texto.isEmpty && _anexo == null && img == null) return;
    // Junta o anexo (clip) e/ou a imagem à mensagem, se houver.
    var conteudo = _anexo == null
        ? texto
        : (texto.isEmpty ? _anexo! : '$texto\n\n--- Anexo ---\n${_anexo!}');
    if (img != null) {
      conteudo = conteudo.isEmpty
          ? '[📷 imagem anexada]'
          : '$conteudo\n[📷 imagem anexada]';
    }
    _ctrl.clear();
    setState(() {
      _conv.mensagens = [..._conv.mensagens, ChatMessage.usuario(conteudo)];
      _conv.talvezTitular();
      _enviando = true;
      _inicioEnvio = DateTime.now();
      _anexo = null;
      _imagemB64 = null;
    });
    // Conta o tempo de espera (segundos.décimos), atualizando a cada 100ms.
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
    ChatStore.salvar(_conv);
    ChatStore.marcarUltima(_conv.id);
    _rolarFim();

    final res = await ChatService.enviar(_conv.mensagens,
        presetId: _conv.preset.id, modeloId: _conv.modelo.id, imagemB64: img);
    _tick?.cancel();
    if (!mounted) return;
    setState(() {
      _conv.mensagens = [
        ..._conv.mensagens,
        ChatMessage.ia(res.sucesso ? res.reply! : '⚠️ ${res.erro}'),
      ];
      _enviando = false;
    });
    ChatStore.salvar(_conv);
    _rolarFim();
    _foco.requestFocus();
  }

  Future<void> _novaConversa() async {
    if (!_conv.vazia) await ChatStore.salvar(_conv);
    setState(() => _conv = Conversa.nova(_conv.preset));
    ChatStore.marcarUltima(_conv.id);
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
                          '${conv.preset.rotulo} · ${_data(conv.atualizadaEm)}'),
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
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() => _conv = conv);
                        ChatStore.marcarUltima(conv.id);
                        _rolarFim();
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

  void _acaoMenu(String v) {
    switch (v) {
      case 'nova':
        _novaConversa();
      case 'resumo':
        _resumir();
      case 'renomear':
        _renomear(_conv);
      default:
        if (v.startsWith('m_')) {
          setState(() => _conv.modelo = ChatModelo.deId(v.substring(2)));
          ChatStore.salvar(_conv);
          _snack('Modelo: ${_conv.modelo.rotulo}');
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
            onSelected: (p) => setState(() => _conv.preset = p),
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
            'Entre com sua conta Google para usar o Muse.\n'
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
      if (_conv.preset == ChatPreset.coach)
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            'Modo Coach Calis Timer',
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
                  if (i == _conv.mensagens.length) return _pensando(context);
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
                ? 'Peça uma análise do seu treino, ou diga "oi" que o Muse te dá o panorama.'
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
    return Align(
      alignment: ehEu ? Alignment.centerRight : Alignment.centerLeft,
      // Segurar = copia a mensagem INTEIRA (sem precisar selecionar tudo).
      child: GestureDetector(
        onLongPress: () => _copiar(m.texto),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: EdgeInsets.fromLTRB(14, 10, ehEu ? 14 : 6, ehEu ? 10 : 2),
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
                        padding: const EdgeInsets.only(right: 8), child: texto),
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
            title: const Text('Anexar imagem'),
            subtitle: const Text('O Muse analisa a foto (visão)'),
            onTap: () => Navigator.pop(c, 'imagem'),
          ),
          ListTile(
            leading: const Icon(Icons.smart_display_outlined),
            title: const Text('Vídeo do YouTube (link)'),
            subtitle: const Text('Transcrever ou resumir pelo link'),
            onTap: () => Navigator.pop(c, 'youtube'),
          ),
        ]),
      ),
    );
    if (escolha == 'texto') await _anexarTexto();
    if (escolha == 'arquivo') await _anexarArquivo();
    if (escolha == 'imagem') await _anexarImagem();
    if (escolha == 'youtube') await _youtube();
  }

  /// Pede ao proxy a transcrição ou o resumo de um vídeo do YouTube (pelo link).
  Future<void> _youtube() async {
    final ctrl = TextEditingController();
    final acao = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Vídeo do YouTube'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'Cole o link do vídeo…'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(c, 'transcricao'),
              child: const Text('Transcrição')),
          FilledButton(
              onPressed: () => Navigator.pop(c, 'resumo'),
              child: const Text('Resumo')),
        ],
      ),
    );
    final url = ctrl.text.trim();
    if (acao == null || url.isEmpty || !mounted) return;
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));
    final res = await ChatService.youtube(url, acao, _conv.modelo.id);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // fecha o loading
    if (!res.sucesso) {
      _snack('⚠️ ${res.erro}');
      return;
    }
    final tit = res.titulo ?? 'vídeo do YouTube';
    if (acao == 'transcricao') {
      setState(() => _anexo = 'Transcrição do vídeo "$tit":\n${res.texto}');
      _snack('Transcrição anexada — escreva o que quer saber dela.');
      return;
    }
    final texto = 'Resumo do vídeo "$tit":\n\n${res.texto}';
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Resumo do vídeo'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(texto)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Fechar')),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: texto));
              Navigator.pop(c);
              _snack('Resumo copiado');
            },
            child: const Text('Copiar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              setState(() => _conv.mensagens = [
                    ..._conv.mensagens,
                    ChatMessage.ia(texto)
                  ]);
              ChatStore.salvar(_conv);
              _rolarFim();
            },
            child: const Text('Inserir'),
          ),
        ],
      ),
    );
  }

  Future<void> _anexarImagem() async {
    try {
      final x = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1280, imageQuality: 70);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() => _imagemB64 = base64Encode(bytes));
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
              const InputDecoration(hintText: 'Cole aqui o texto para o Muse analisar…'),
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
          if (_anexo != null || _imagemB64 != null)
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
                  if (_imagemB64 != null)
                    Chip(
                      avatar: const Icon(Icons.image, size: 16),
                      label: const Text('Imagem anexada'),
                      onDeleted: () => setState(() => _imagemB64 = null),
                    ),
                ]),
              ),
            ),
          Row(children: [
            IconButton(
              icon: Icon(Icons.attach_file,
                  color: (_anexo != null || _imagemB64 != null)
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
            FloatingActionButton.small(
              heroTag: 'fab_chat_enviar',
              onPressed: _enviando ? null : _enviar,
              tooltip: 'Enviar',
              child: Icon(_enviando ? Icons.hourglass_empty : Icons.send),
            ),
          ]),
        ]),
      ),
    );
  }
}
