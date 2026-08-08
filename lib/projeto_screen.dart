import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'caixa3d.dart';
import 'cores.dart';
import 'editor.dart';
import 'models.dart';
import 'storage.dart';
import 'titulo_destacado.dart';

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

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
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
      texto: '1- ',
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
    if (itens.isEmpty) {
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
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      itemCount: itens.length,
      buildDefaultDragHandles: false,
      onReorderItem: (a, n) => _reordenar(aba, a, n),
      itemBuilder: (_, i) => Padding(
        key: ValueKey(itens[i].id),
        padding: const EdgeInsets.only(bottom: 10),
        child: _CaixaNota(
          key: _chaveDa(itens[i].id),
          nota: itens[i],
          indice: i,
          onCopiar: () => copiarTexto(context, itens[i].texto),
          onExcluir: () => _excluir(aba, i),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TituloDestacado(widget.projeto.nome),
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
    required this.onCopiar,
    required this.onExcluir,
  });

  final Nota nota;
  final int indice;
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

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.nota.texto);
  }

  @override
  void dispose() {
    _debounce?.cancel();
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

  void _proximoItem() {
    final linha = '${proximoNumeroLista(_ctrl.text)}- ';
    final novo = _ctrl.text.isEmpty || _ctrl.text.endsWith('\n')
        ? _ctrl.text + linha
        : '${_ctrl.text}\n$linha';
    _ctrl.value = TextEditingValue(
      text: novo,
      selection: TextSelection.collapsed(offset: novo.length),
    );
    _foco.requestFocus();
    _mudou(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.luz;
    return Caixa3D(
      cor: app.notaInicio,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ReorderableDragStartListener(
                  index: widget.indice,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 22,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BotaoMini(
                      icone: Icons.format_list_numbered,
                      tooltip: 'Adicionar item da lista',
                      onTap: _proximoItem,
                    ),
                    _BotaoMini(
                      icone: Icons.copy_all_outlined,
                      tooltip: 'Copiar',
                      onTap: widget.onCopiar,
                    ),
                    _BotaoMini(
                      icone: Icons.edit_outlined,
                      tooltip: 'Editar',
                      onTap: _foco.requestFocus,
                    ),
                    _BotaoMini(
                      icone: Icons.cleaning_services,
                      tooltip: 'Limpar conteúdo',
                      onTap: _limpar,
                    ),
                    _BotaoMini(
                      icone: Icons.delete_outline,
                      tooltip: 'Excluir',
                      isDanger: true,
                      onTap: widget.onExcluir,
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
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onTap: focarNoFim,
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
  });

  final IconData icone;
  final String tooltip;
  final VoidCallback onTap;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icone,
          size: 20,
          color: isDanger
              ? Colors.red
              : Theme.of(context).colorScheme.onSurfaceVariant),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}