import 'package:flutter/material.dart';

import '../muse_blob.dart';
import 'chat_models.dart';
import 'chat_screen.dart';
import 'chat_store.dart';

/// LISTA de conversas da Muse — a aba "Muse" da barra inferior abre AQUI primeiro
/// (V0.1.173). Tocar numa conversa abre o chat (`ChatScreen`), que tem um voltar
/// que retorna para esta lista. "Nova conversa" começa uma limpa.
class ConversasScreen extends StatefulWidget {
  const ConversasScreen({super.key});

  @override
  State<ConversasScreen> createState() => _ConversasScreenState();
}

class _ConversasScreenState extends State<ConversasScreen> {
  List<Conversa> _convs = [];
  bool _carregando = true;
  String _filtro = '';
  bool _buscando = false;
  final _buscaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final convs = await ChatStore.listar(); // já vem da mais recente p/ a antiga
    if (!mounted) return;
    setState(() {
      _convs = convs;
      _carregando = false;
    });
  }

  Future<void> _abrir(String id) async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatScreen(conversaId: id)));
    await _carregar(); // títulos/ordem podem ter mudado
  }

  Future<void> _nova() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ChatScreen(iniciarNova: true)));
    await _carregar();
  }

  Future<void> _acoes(Conversa conv) async {
    final acao = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Renomear'),
            onTap: () => Navigator.pop(c, 'renomear'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Apagar conversa'),
            onTap: () => Navigator.pop(c, 'apagar'),
          ),
        ]),
      ),
    );
    if (acao == 'renomear') await _renomear(conv);
    if (acao == 'apagar') await _apagar(conv);
  }

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
      await _carregar();
    }
  }

  Future<void> _apagar(Conversa conv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Apagar conversa?'),
        content: Text('"${conv.titulo}" será removida deste aparelho.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child:
                  const Text('Apagar', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await ChatStore.remover(conv.id);
      await _carregar();
    }
  }

  String _data(DateTime d) {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final dia = DateTime(d.year, d.month, d.day);
    final difDias = hoje.difference(dia).inDays;
    if (difDias <= 0) return 'hoje';
    if (difDias == 1) return 'ontem';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _filtro.trim().toLowerCase();
    final lista = q.isEmpty
        ? _convs
        : _convs
            .where((c) => c.titulo.toLowerCase().contains(q))
            .toList(growable: false);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                // Cabeçalho com o rosto da Muse.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                  child: Column(children: [
                    MuseBlob(size: 72),
                    const SizedBox(height: 10),
                    Text('Muse Spark',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface)),
                    const SizedBox(height: 2),
                    Text('escolha uma conversa ou comece outra',
                        style:
                            TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                  ]),
                ),
                // Barra: "Conversas" + buscar + nova.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 10, 4),
                  child: _buscando
                      ? Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _buscaCtrl,
                              autofocus: true,
                              onChanged: (v) => setState(() => _filtro = v),
                              decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: 'Buscar conversa…',
                                  border: InputBorder.none),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Fechar busca',
                            onPressed: () => setState(() {
                              _buscando = false;
                              _filtro = '';
                              _buscaCtrl.clear();
                            }),
                          ),
                        ])
                      : Row(children: [
                          Expanded(
                            child: Text('CONVERSAS',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                    color: cs.onSurfaceVariant)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.search),
                            tooltip: 'Buscar conversa',
                            onPressed: _convs.isEmpty
                                ? null
                                : () => setState(() => _buscando = true),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_comment_outlined),
                            tooltip: 'Nova conversa',
                            onPressed: _nova,
                          ),
                        ]),
                ),
                Expanded(
                  child: lista.isEmpty
                      ? _vazio(context)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          itemCount: lista.length,
                          itemBuilder: (c, i) {
                            final conv = lista[i];
                            return Card(
                              elevation: 0,
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                title: Text(conv.titulo,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                    '${conv.preset.rotulo} · ${conv.tamanho.rotulo} · ${_data(conv.atualizadaEm)}'),
                                onTap: () => _abrir(conv.id),
                                onLongPress: () => _acoes(conv),
                              ),
                            );
                          },
                        ),
                ),
              ]),
      ),
    );
  }

  Widget _vazio(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              _filtro.isEmpty
                  ? 'Nenhuma conversa ainda.\nToque em "Nova conversa" para começar.'
                  : 'Nenhuma conversa com esse nome.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ]),
        ),
      );
}
