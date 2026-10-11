import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final _scroll = ScrollController();
  final _foco = FocusNode();
  Conversa _conv = Conversa.nova(ChatPreset.coach);
  bool _enviando = false;
  bool _carregando = true;
  Timer? _tick; // atualiza o contador do "pensando"
  DateTime? _inicioEnvio;
  String? _anexo; // texto anexado (clip) p/ a próxima mensagem

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
    _carregar();
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

  // Lista é invertida (reverse:true) → o fim (mensagem mais recente) é o offset 0,
  // sempre visível ao abrir, sem precisar rolar.
  void _rolarFim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    final texto = capitalizarFrases(_ctrl.text.trim());
    if (texto.isEmpty && _anexo == null) return;
    // Junta o anexo (clip) à mensagem, se houver.
    final conteudo = _anexo == null
        ? texto
        : (texto.isEmpty ? _anexo! : '$texto\n\n--- Anexo ---\n${_anexo!}');
    _ctrl.clear();
    setState(() {
      _conv.mensagens = [..._conv.mensagens, ChatMessage.usuario(conteudo)];
      _conv.talvezTitular();
      _enviando = true;
      _inicioEnvio = DateTime.now();
      _anexo = null;
    });
    // Conta o tempo de espera (segundos.décimos), atualizando a cada 100ms.
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
    ChatStore.salvar(_conv);
    ChatStore.marcarUltima(_conv.id);
    _rolarFim();

    final res = await ChatService.enviar(_conv.mensagens, _conv.preset);
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
        // Mostra o NOME da conversa (fonte menor, até 2 linhas — os botões ocupam
        // espaço). Segure uma conversa no histórico para renomear.
        title: Text(
          _conv.titulo,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, height: 1.1),
        ),
        actions: [
          IconButton(
            tooltip: 'Conversas',
            icon: const Icon(Icons.history),
            onPressed: _abrirHistorico,
          ),
          IconButton(
            tooltip: 'Nova conversa',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _novaConversa,
          ),
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
            'Modo Coach: o Muse considera seu desempenho no Calis Timer.',
            style: TextStyle(
                fontSize: 12, color: Theme.of(context).colorScheme.primary),
          ),
        ),
      Expanded(
        child: _conv.vazia
            ? _vazio(context)
            : ListView.builder(
                controller: _scroll,
                reverse: true, // i=0 = mensagem mais recente (embaixo)
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                itemCount: _conv.mensagens.length + (_enviando ? 1 : 0),
                itemBuilder: (c, i) {
                  if (_enviando && i == 0) return _pensando(context);
                  final idx =
                      _conv.mensagens.length - 1 - (i - (_enviando ? 1 : 0));
                  return _bolha(context, _conv.mensagens[idx]);
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

  Widget _bolha(BuildContext context, ChatMessage m) {
    final cs = Theme.of(context).colorScheme;
    final ehEu = m.ehUsuario;
    return Align(
      alignment: ehEu ? Alignment.centerRight : Alignment.centerLeft,
      // Segurar = copia a mensagem INTEIRA (sem precisar selecionar tudo).
      child: GestureDetector(
        onLongPress: () => _copiar(m.texto),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          child: Text(
            m.texto,
            style: TextStyle(
                color: ehEu ? cs.onPrimary : cs.onSurface, height: 1.3),
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
        ]),
      ),
    );
    if (escolha == 'texto') await _anexarTexto();
    if (escolha == 'arquivo') await _anexarArquivo();
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
          if (_anexo != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Chip(
                  avatar: const Icon(Icons.attach_file, size: 16),
                  label: Text('Anexo (${_anexo!.length} caracteres)'),
                  onDeleted: () => setState(() => _anexo = null),
                ),
              ),
            ),
          Row(children: [
            IconButton(
              icon: Icon(Icons.attach_file,
                  color: _anexo != null
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
