import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'caixa3d.dart';
import 'cores.dart';
import 'editor.dart';
import 'models.dart';
import 'storage.dart';

/// Página de um projeto dividida em duas abas: "Tarefas" (atuais) e "Futuro".
class ProjetoScreen extends StatefulWidget {
  const ProjetoScreen({super.key, required this.projeto});

  final Projeto projeto;

  @override
  State<ProjetoScreen> createState() => _ProjetoScreenState();
}

class _ProjetoScreenState extends State<ProjetoScreen>
    with SingleTickerProviderStateMixin {
  final Map<String, GlobalKey<_CaixaNotaState>> _chaves = {};
  late final TabController _tabCtrl;
  final TextEditingController _ctrlBusca = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _ctrlBusca.dispose();
    super.dispose();
  }

  Future<void> _salvar() => Storage.instance.salvar();

  GlobalKey<_CaixaNotaState> _chaveDa(String id) =>
      _chaves.putIfAbsent(id, () => GlobalKey<_CaixaNotaState>());

  List<Nota> _lista(int aba) =>
      aba == 0 ? widget.projeto.tarefas : widget.projeto.futuro;

  void _adicionar(int aba) {
    final nota = Nota(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      texto: aba == 0 ? '1- ' : '',
    );
    setState(() => _lista(aba).add(nota));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chaveDa(nota.id).currentState?.focarNoFim();
    });
    _salvar();
  }

  void _excluir(int aba, int i) {
    setState(() => _lista(aba).removeAt(i));
    _salvar();
  }

  void _reordenar(int aba, int antigo, int novo) {
    setState(() {
      final lst = _lista(aba);
      final n = lst.removeAt(antigo);
      lst.insert(novo, n);
    });
    _salvar();
  }

  void _copiarProjeto() {
    final p = widget.projeto;
    final buf = StringBuffer()
      ..writeln(p.nome)
      ..writeln('=' * 32);
    if (p.tarefas.isNotEmpty) {
      for (final n in p.tarefas) {
        for (final linha in n.texto.split('\n')) {
          buf.writeln('  $linha');
        }
      }
    }
    if (p.futuro.isNotEmpty) {
      buf.writeln('  --- Futuro ---');
      for (final n in p.futuro) {
        for (final linha in n.texto.split('\n')) {
          buf.writeln('  $linha');
        }
      }
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Projeto copiado!')));
  }

  Widget _listaCard(int aba) {
    final itens = _lista(aba);
    final ehTarefas = aba == 0;

    if (ehTarefas && itens.isEmpty ||
        !ehTarefas && itens.isEmpty && _ctrlBusca.text.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.format_list_numbered, size: 56,
                  color: Colors.grey),
              const SizedBox(height: 16),
              const Text('Nenhuma caixa ainda',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                'Toque no + para criar a primeira caixa de texto.',
                style: TextStyle(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final filtradas = ehTarefas
        ? itens
        : itens.where((n) =>
            _ctrlBusca.text.isEmpty ||
            n.texto.toLowerCase().contains(_ctrlBusca.text.toLowerCase())).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!ehTarefas)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: TextField(
              controller: _ctrlBusca,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Buscar no Futuro…',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        Expanded(
          child: filtradas.isEmpty
              ? const Center(
                  child: Text('Nada encontrado.',
                      style: TextStyle(color: Colors.grey)))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 150),
                  itemCount: filtradas.length,
                  buildDefaultDragHandles: false,
                  onReorderItem: (a, n) {
                    final lst = _lista(aba);
                    final antigo = lst.indexOf(filtradas[a]);
                    final novo = lst.indexOf(filtradas[n]);
                    _reordenar(aba, antigo, novo);
                  },
                  itemBuilder: (_, i) => Padding(
                    key: ValueKey(filtradas[i].id),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CaixaNota(
                      key: _chaveDa(filtradas[i].id),
                      nota: filtradas[i],
                      indice: _lista(aba).indexOf(filtradas[i]),
                      modoTarefas: ehTarefas,
                      onCopiar: () =>
                          copiarTexto(context, filtradas[i].texto),
                      onExcluir: () =>
                          _excluir(aba, _lista(aba).indexOf(filtradas[i])),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.projeto.nome),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.copy_outlined, size: 18),
              tooltip: 'Copiar tudo do projeto',
              onPressed: _copiarProjeto,
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: const [
            Tab(text: 'Tarefas'),
            Tab(text: 'Futuro'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _adicionar(_tabCtrl.index),
        tooltip: 'Nova caixa de texto',
        child: const Icon(Icons.add),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _listaCard(0),
          _listaCard(1),
        ],
      ),
    );
  }
}

class _CaixaNota extends StatefulWidget {
  const _CaixaNota({
    super.key,
    required this.nota,
    required this.indice,
    required this.modoTarefas,
    required this.onCopiar,
    required this.onExcluir,
  });

  final Nota nota;
  final int indice;

  /// Se false (modo Futuro), não mostra botão de lista numerada nem inicia
  /// novas caixinhas com "1- ".
  final bool modoTarefas;

  final VoidCallback onCopiar;
  final VoidCallback onExcluir;

  @override
  State<_CaixaNota> createState() => _CaixaNotaState();
}

class _CaixaNotaState extends State<_CaixaNota> {
  late final TextEditingController _ctrl;
  final FocusNode _foco = FocusNode();
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;
  Timer? _debounceYT;
  bool _numerado = true;
  bool _comentarioExpandido = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.nota.texto);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _debounceYT?.cancel();
    Storage.instance.salvar();
    _ctrl.dispose();
    _foco.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void focarNoFim() {
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    _foco.requestFocus();
  }

  void _mudou(String novoTexto) {
    widget.nota.texto = novoTexto;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      final corrigido = maiusculaAposItem(_ctrl.text);
      if (corrigido != _ctrl.text) {
        _ctrl.value = TextEditingValue(
          text: corrigido,
          selection: TextSelection.collapsed(offset: corrigido.length),
        );
        widget.nota.texto = corrigido;
      }
      Storage.instance.salvar();
    });
  }

  void _limpar() {
    _ctrl.clear();
    _mudou('');
  }

  void _alternarConcluida() {
    setState(() => widget.nota.concluida = !widget.nota.concluida);
    Storage.instance.salvar();
  }

  void _inserirLinha() {
    final base = _ctrl.text.trimRight();
    String adicao;
    if (_numerado) {
      adicao = '\n${proximoNumeroLista(_ctrl.text)}- ';
    } else {
      adicao = '\n';
    }
    final novo = _ctrl.text.isEmpty ? adicao.trimLeft() : '$base$adicao';
    _ctrl.value = TextEditingValue(
      text: novo,
      selection: TextSelection.collapsed(offset: novo.length),
    );
    _foco.requestFocus();
    _mudou(_ctrl.text);
    setState(() => _numerado = !_numerado);
  }

  Future<void> _abrirLink() async {
    final ctrl = TextEditingController(text: widget.nota.link ?? '');
    String? titulo;
    bool buscando = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.url,
                onChanged: (v) {
                  _debounceYT?.cancel();
                  if (v.contains('youtube.com') || v.contains('youtu.be')) {
                    setSt(() => buscando = true);
                    _debounceYT = Timer(const Duration(milliseconds: 600), () async {
                      try {
                        final t = await _tituloYouTube(v);
                        if (ctx.mounted) {
                          setSt(() { titulo = t; buscando = false; });
                        }
                      } catch (_) {
                        if (ctx.mounted) setSt(() => buscando = false);
                      }
                    });
                  } else {
                    setSt(() { titulo = null; buscando = false; });
                  }
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'https://…',
                ),
              ),
              if (buscando)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (titulo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    titulo!,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.65),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => ctrl.clear(), child: const Text('Limpar')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
            if (widget.nota.link != null && widget.nota.link!.isNotEmpty)
              TextButton(onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.nota.link!));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(content: Text('Link copiado!')));
              }, child: const Text('Copiar link')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final raw = ctrl.text.trim();
    widget.nota.link = raw.isEmpty ? null : raw;

    // Se encontrou título do YouTube, salva no comentário (se vazio).
    if (titulo != null && (widget.nota.comentario ?? '').isEmpty) {
      widget.nota.comentario = titulo;
    }
    Storage.instance.salvar();
  }

  Future<String?> _tituloYouTube(String url) async {
    final uri = Uri.parse(url);
    String? videoId;
    if (uri.host.contains('youtu.be')) {
      videoId = uri.pathSegments.firstOrNull;
    } else {
      videoId = uri.queryParameters['v'];
    }
    if (videoId == null || videoId.isEmpty) return null;

    final api = Uri.parse(
        'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json');
    final req = await HttpClient().getUrl(api);
    req.headers.set('User-Agent', 'Mozilla/5.0');
    final res = await req.close();
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['title'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.luz;
    final corFerramentas = app.barraFerramentas;
    final onBarra = ThemeData.estimateBrightnessForColor(corFerramentas) ==
            Brightness.dark
        ? Colors.white
        : Colors.black87;

    return Caixa3D(
      cor: app.notaInicio,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barra de ferramentas com cor separada
          Container(
            decoration: BoxDecoration(
              color: corFerramentas,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14)),
            ),
            padding: const EdgeInsets.fromLTRB(10, 4, 6, 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ReorderableDragStartListener(
                  index: widget.indice,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 22,
                    color: onBarra.withValues(alpha: 0.7),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BotaoMini(
                      icone: widget.nota.concluida
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      tooltip: widget.nota.concluida ? 'Desmarcar' : 'Marcar como feito',
                      onTap: _alternarConcluida,
                      cor: onBarra,
                    ),
                    if (widget.modoTarefas)
                      _BotaoMini(
                        icone: _numerado
                            ? Icons.format_list_numbered
                            : Icons.format_align_justify,
                        tooltip: _numerado
                            ? 'Lista numerada (ligada)'
                            : 'Nova linha (sem número)',
                        onTap: _inserirLinha,
                        cor: onBarra,
                      ),
                    _BotaoMini(
                      icone: Icons.add_link,
                      tooltip: 'Link',
                      onTap: _abrirLink,
                      cor: onBarra,
                    ),
                    _BotaoMini(
                      icone: _comentarioExpandido
                          ? Icons.chat_bubble
                          : Icons.chat_bubble_outline,
                      tooltip: 'Comentário',
                      onTap: () =>
                          setState(() => _comentarioExpandido = !_comentarioExpandido),
                      cor: onBarra,
                    ),
                    _BotaoMini(
                      icone: Icons.copy_all_outlined,
                      tooltip: 'Copiar',
                      onTap: widget.onCopiar,
                      cor: onBarra,
                    ),
                    _BotaoMini(
                      icone: Icons.edit_outlined,
                      tooltip: 'Editar',
                      onTap: focarNoFim,
                      cor: onBarra,
                    ),
                    _BotaoMini(
                      icone: Icons.cleaning_services,
                      tooltip: 'Limpar conteúdo',
                      onTap: _limpar,
                      cor: onBarra,
                    ),
                    _BotaoMini(
                      icone: Icons.delete_outline,
                      tooltip: 'Excluir',
                      isDanger: true,
                      onTap: widget.onExcluir,
                      cor: onBarra,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Scrollbar(
            controller: _scroll,
            child: TextField(
              scrollController: _scroll,
              controller: _ctrl,
              focusNode: _foco,
              minLines: 1,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [LinhasNumeradas()],
              style: TextStyle(
                fontSize: 14.5,
                height: 1.35,
                color: widget.nota.concluida
                    ? Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.45)
                    : Theme.of(context).colorScheme.onSurface,
              ),
              onChanged: _mudou,
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.fromLTRB(14, 2, 14, 14),
              ),
            ),
          ),
          // Subcaixinha de comentário inline (abaixo com letra mais fraca)
          if (_comentarioExpandido)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: app.notaFim.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14)),
              ),
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: TextField(
                controller: TextEditingController(
                    text: widget.nota.comentario ?? ''),
                onChanged: (v) {
                  widget.nota.comentario = v.isEmpty ? null : v;
                  Storage.instance.salvar();
                },
                maxLines: 3,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  hintText: 'Comentário…',
                ),
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BotaoMini extends StatelessWidget {
  const _BotaoMini({
    required this.icone,
    required this.tooltip,
    required this.onTap,
    this.isDanger = false,
    this.cor,
  });

  final IconData icone;
  final String tooltip;
  final VoidCallback onTap;
  final bool isDanger;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icone,
          size: 20,
          color: isDanger
              ? Colors.red
              : (cor ?? Theme.of(context).colorScheme.onSurfaceVariant)),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}