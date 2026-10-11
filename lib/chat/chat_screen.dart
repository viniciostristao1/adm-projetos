import 'package:flutter/material.dart';

import '../sync_service.dart';
import 'chat_models.dart';
import 'chat_service.dart';
import 'chat_store.dart';

/// Janela de chat com a IA (módulo isolado — só é aberta pelo botão de mensagem,
/// que por sua vez só existe com a flag de compilação `CHAT`). A auth é o login
/// Google que o app já usa (`SyncService`); o servidor só aceita a conta do dono.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _foco = FocusNode();
  List<ChatMessage> _msgs = [];
  ChatPreset _preset = ChatPreset.livre;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    SyncService.instance.addListener(_aoMudarAuth);
    ChatStore.carregar().then((m) {
      if (!mounted) return;
      setState(() => _msgs = m);
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
      _msgs = [..._msgs, ChatMessage.usuario(texto)];
      _enviando = true;
    });
    ChatStore.salvar(_msgs);
    _rolarFim();

    final res = await ChatService.enviar(_msgs, _preset);
    if (!mounted) return;
    setState(() {
      _msgs = [
        ..._msgs,
        ChatMessage.ia(res.sucesso ? res.reply! : '⚠️ ${res.erro}'),
      ];
      _enviando = false;
    });
    ChatStore.salvar(_msgs);
    _rolarFim();
    _foco.requestFocus();
  }

  Future<void> _limpar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Limpar conversa?'),
        content: const Text('Apaga as mensagens deste chat (só neste aparelho).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Limpar')),
        ],
      ),
    );
    if (ok != true) return;
    await ChatStore.limpar();
    if (mounted) setState(() => _msgs = []);
  }

  @override
  Widget build(BuildContext context) {
    final logado = SyncService.instance.conectado;
    return Scaffold(
      appBar: AppBar(
        // Mostra o MODO ativo no título (evita confundir Conversa × Coach).
        title: Text('Chat · ${_preset.rotulo}'),
        actions: [
          PopupMenuButton<ChatPreset>(
            tooltip: 'Modo',
            initialValue: _preset,
            onSelected: (p) => setState(() => _preset = p),
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
              Icon(_preset == ChatPreset.coach
                  ? Icons.fitness_center
                  : Icons.forum_outlined),
              const Icon(Icons.arrow_drop_down),
            ]),
          ),
          if (_msgs.isNotEmpty)
            IconButton(
              tooltip: 'Limpar conversa',
              icon: const Icon(Icons.delete_outline),
              onPressed: _limpar,
            ),
        ],
      ),
      body: logado ? _conversa(context) : _conviteLogin(context),
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
            'Entre com sua conta Google para usar o chat.\n'
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
      if (_preset == ChatPreset.coach)
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            'Modo Coach: a IA considera seu desempenho no Calis Timer.',
            style: TextStyle(
                fontSize: 12, color: Theme.of(context).colorScheme.primary),
          ),
        ),
      Expanded(
        child: _msgs.isEmpty
            ? _vazio(context)
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                itemCount: _msgs.length + (_enviando ? 1 : 0),
                itemBuilder: (c, i) {
                  if (i == _msgs.length) return _pensando(context);
                  return _bolha(context, _msgs[i]);
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
            _preset == ChatPreset.coach
                ? 'Peça uma análise do seu treino, ou conte como foi o dia.'
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
              // Teclado capitaliza o início de cada frase enquanto você digita.
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
