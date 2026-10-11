import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    SyncService.instance.addListener(_aoMudarAuth);
    ChatStore.listar().then((convs) {
      if (!mounted) return;
      setState(() {
        if (convs.isNotEmpty) _conv = convs.first;
        _carregando = false;
      });
      _rolarFim();
    });
  }

  @override
  void dispose() {
    SyncService.instance.removeListener(_aoMudarAuth);
    _ctrl.dispose();
    _scroll.dispose();
    _foco.dispose();
    super.dispose();
  }

  void _aoMudarAuth() {
    if (mounted) setState(() {});
  }

  void _rolarFim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _enviar() async {
    final texto = capitalizarFrases(_ctrl.text.trim());
    if (texto.isEmpty || _enviando) return;
    _ctrl.clear();
    setState(() {
      _conv.mensagens = [..._conv.mensagens, ChatMessage.usuario(texto)];
      _conv.talvezTitular();
      _enviando = true;
    });
    ChatStore.salvar(_conv);
    _rolarFim();

    final res = await ChatService.enviar(_conv.mensagens, _conv.preset);
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
                      leading: Icon(conv.preset == ChatPreset.coach
                          ? Icons.fitness_center
                          : Icons.forum_outlined),
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
                        _rolarFim();
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
        title: Text('Muse · ${_conv.preset.rotulo}'),
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
                    leading: Icon(p == ChatPreset.coach
                        ? Icons.fitness_center
                        : Icons.forum_outlined),
                    title: Text(p.rotulo),
                    subtitle: Text(p.descricao),
                  ),
                ),
            ],
            icon: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_conv.preset == ChatPreset.coach
                  ? Icons.fitness_center
                  : Icons.forum_outlined),
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
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                itemCount: _conv.mensagens.length + (_enviando ? 1 : 0),
                itemBuilder: (c, i) {
                  if (i == _conv.mensagens.length) return _pensando(context);
                  return _bolha(context, _conv.mensagens[i]);
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
        child: SelectableText(
          m.texto,
          style: TextStyle(
              color: ehEu ? cs.onPrimary : cs.onSurface, height: 1.3),
        ),
      ),
    );
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
            Text('pensando…', style: TextStyle(color: Theme.of(context).hintColor)),
          ]),
        ),
      );

  Widget _barraEntrada(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Row(children: [
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
      ),
    );
  }
}
