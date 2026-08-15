import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'caixa3d.dart';
import 'cores.dart';
import 'editor.dart';
import 'models.dart';
import 'pdf_export.dart';
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
  final FocusNode _focoBusca = FocusNode();
  bool _buscando = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _ctrlBusca.dispose();
    _focoBusca.dispose();
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
    final lst = _lista(aba);
    final nota = lst[i];
    setState(() => lst.removeAt(i));
    _salvar();
    mostrarAvisoAcao(
      context,
      'Caixinha excluída',
      'Desfazer',
      () {
        setState(() => lst.insert(i > lst.length ? lst.length : i, nota));
        _salvar();
      },
    );
  }

  /// Move a caixinha para a OUTRA aba (Tarefas <-> Futuro), com desfazer.
  void _moverOutraAba(int aba, int i) {
    final nota = _lista(aba).removeAt(i);
    final destino = aba == 0 ? widget.projeto.futuro : widget.projeto.tarefas;
    destino.add(nota);
    final nomeDestino = aba == 0 ? 'Futuro' : 'Tarefas';
    setState(() {});
    _salvar();
    mostrarAvisoAcao(
      context,
      'Movida para $nomeDestino',
      'Desfazer',
      () {
        setState(() {
          destino.remove(nota);
          final lst = _lista(aba);
          lst.insert(i > lst.length ? lst.length : i, nota);
        });
        _salvar();
      },
    );
  }

  /// Abre/fecha o campo de busca da aba ativa.
  void _alternarBusca() {
    setState(() {
      _buscando = !_buscando;
      if (!_buscando) _ctrlBusca.clear();
    });
    if (_buscando) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focoBusca.requestFocus();
      });
    }
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
    mostrarAviso(context, 'Projeto copiado!');
  }

  Widget _listaCard(int aba) {
    final itens = _lista(aba);
    final ehTarefas = aba == 0;

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

    final q = _ctrlBusca.text.trim().toLowerCase();
    final filtradas = q.isEmpty
        ? itens
        : itens.where((n) =>
            n.texto.toLowerCase().contains(q) ||
            (n.comentario ?? '').toLowerCase().contains(q)).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_buscando)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Builder(builder: (ctx) {
              final app = Theme.of(ctx).extension<AppCores>() ?? AppCores.azul;
              final preencher = app.neumorfico;
              return TextField(
                controller: _ctrlBusca,
                focusNode: _focoBusca,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: ehTarefas
                      ? 'Buscar em Tarefas…'
                      : 'Buscar no Futuro…',
                  isDense: true,
                  filled: preencher,
                  fillColor: preencher ? app.notaFim : null,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (_) => setState(() {}),
              );
            }),
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
                      onMover: () => _moverOutraAba(
                          aba, _lista(aba).indexOf(filtradas[i])),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Fundo(
      child: Scaffold(
        appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.projeto.nome),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              tooltip: 'Exportar PDF do projeto',
              onPressed: () => exportarPdfProjeto(context, widget.projeto),
            ),
            IconButton(
              icon: const Icon(Icons.copy_outlined, size: 18),
              tooltip: 'Copiar tudo do projeto',
              onPressed: _copiarProjeto,
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kTextTabBarHeight),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabCtrl,
                  indicatorSize: TabBarIndicatorSize.tab,
                  tabs: const [
                    Tab(text: 'Tarefas'),
                    Tab(text: 'Futuro'),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(_buscando ? Icons.close : Icons.search),
                tooltip: _buscando ? 'Fechar busca' : 'Buscar na aba',
                onPressed: _alternarBusca,
              ),
            ],
          ),
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
    required this.onMover,
  });

  final Nota nota;
  final int indice;

  /// Se false (modo Futuro), não mostra botão de lista numerada nem inicia
  /// novas caixinhas com "1- ".
  final bool modoTarefas;

  final VoidCallback onCopiar;
  final VoidCallback onExcluir;

  /// Move a caixinha para a outra aba (Tarefas <-> Futuro).
  final VoidCallback onMover;

  @override
  State<_CaixaNota> createState() => _CaixaNotaState();
}

class _CaixaNotaState extends State<_CaixaNota> {
  late final TextEditingController _ctrl;
  late final TextEditingController _ctrlComentario;
  final FocusNode _foco = FocusNode();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _campoKey = GlobalKey();
  Timer? _debounce;
  Timer? _debounceYT;
  Timer? _timerVis;
  double? _alturaMaxima;
  bool _numerado = true;
  bool _comentarioExpandido = false;
  bool _comentarioVisivel = false;
  ScrollPosition? _posExterna;
  double? _insetsAntes;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.nota.texto);
    _ctrlComentario =
        TextEditingController(text: widget.nota.comentario ?? '');
    _foco.addListener(_aoFocar);
    _foco.addListener(_aoPerderFoco);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Recalcula quando o teclado abre/fecha durante a digitação.
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    if (_insetsAntes != null && _insetsAntes != insets && _foco.hasFocus) {
      _agendarAjuste();
    }
    _insetsAntes = insets;
    // Recalcula quando a LISTA rola (a caixinha pode ir parar atrás do "+").
    final sc = Scrollable.maybeOf(context);
    final pos = sc?.position;
    if (!identical(pos, _posExterna)) {
      _posExterna?.removeListener(_aoRolarExterno);
      _posExterna = pos;
      _posExterna?.addListener(_aoRolarExterno);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _debounceYT?.cancel();
    _timerVis?.cancel();
    _posExterna?.removeListener(_aoRolarExterno);
    _foco.removeListener(_aoFocar);
    _foco.removeListener(_aoPerderFoco);
    // Derrama o que está nos controladores direto no modelo e no disco —
    // cobre o texto que a IME ainda não tinha confirmado (composição) quando
    // o usuário sai rápido da tela.
    _guardarTudo();
    _ctrl.dispose();
    _ctrlComentario.dispose();
    _foco.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Grava o conteúdo atual dos controladores no modelo e salva no disco.
  /// Só derrama o comentário se o campo dele está mesmo montado (senão um
  /// controlador antigo sobrescreveria um comentário salvo por outro caminho,
  /// ex.: título do YouTube vindo do diálogo de link).
  void _guardarTudo() {
    widget.nota.texto = _ctrl.text;
    if (_comentarioVisivel) {
      final c = _ctrlComentario.text;
      widget.nota.comentario = c.isEmpty ? null : c;
    }
    Storage.instance.salvar();
  }

  /// Ao PERDER o foco (toque em outra caixinha, voltar de tela, teclado
  /// fechando) derrama o texto na hora — é o sinal mais cedo de que o usuário
  /// parou de digitar naquela caixinha e nada pode ficar só no teclado.
  void _aoPerderFoco() {
    if (_foco.hasFocus) return;
    _guardarTudo();
  }

  void focarNoFim() {
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    _foco.requestFocus();
  }

  /// Ao ganhar foco: rola a lista para a caixinha ficar acima do botão "+"
  /// e trava a altura máxima do texto no espaço disponível. Só roda nesse
  /// momento (e 300ms depois, para o teclado terminar de abrir) — nunca a
  /// cada tecla, para a lista não "tremer" durante a digitação.
  void _aoFocar() {
    if (!_foco.hasFocus) return;
    _ajustarVisibilidade();
    _timerVis?.cancel();
    _timerVis = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _ajustarVisibilidade();
    });
  }

  /// Ajuste com um pequeno atraso (evita rajada de recalculos ao rolar).
  void _agendarAjuste() {
    if (!_foco.hasFocus) return;
    _timerVis?.cancel();
    _timerVis = Timer(const Duration(milliseconds: 120), () {
      if (mounted && _foco.hasFocus) _ajustarVisibilidade();
    });
  }

  /// Ao rolar a lista, a caixinha NÃO é puxada de volta (nada de `jumpTo`
  /// durante o gesto do usuário — era isso que fazia a página "tremer" e
  /// impedia de rolar para cima). Só recalcula a altura travada, e apenas
  /// DEPOIS que a rolagem parar de verdade (o timer reinicia a cada evento
  /// de rolagem; a lista parada não é tocada).
  void _aoRolarExterno() {
    if (!_foco.hasFocus) return;
    _timerVis?.cancel();
    _timerVis = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _foco.hasFocus) _ajustarAltura();
    });
  }

  /// Recalcula só a altura máxima travada (sem mover a lista). Só age com a
  /// rolagem totalmente parada para não brigar com o dedo do usuário.
  void _ajustarAltura() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scrollable = Scrollable.maybeOf(context);
      if (scrollable != null &&
          scrollable.position.isScrollingNotifier.value) {
        return;
      }
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final media = MediaQuery.of(context);
      final limite = media.size.height - media.viewInsets.bottom - 100;
      final topo = box.localToGlobal(Offset.zero).dy;
      final nova = (limite - topo).clamp(96.0, media.size.height * 0.6);
      if (_alturaMaxima == null || (nova - _alturaMaxima!).abs() > 1) {
        setState(() => _alturaMaxima = nova);
      }
    });
  }

  void _ajustarVisibilidade() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final media = MediaQuery.of(context);
      final limite =
          media.size.height - media.viewInsets.bottom - 100;
      var topo = box.localToGlobal(Offset.zero).dy;
      if (limite - topo < 160) {
        final scrollable = Scrollable.of(context);
        if (scrollable.position.hasContentDimensions) {
          scrollable.position.jumpTo(
            (scrollable.position.pixels + (160 - (limite - topo)))
                .clamp(
              scrollable.position.minScrollExtent,
              scrollable.position.maxScrollExtent,
            ),
          );
        }
        topo = limite - 160;
      }
      final nova =
          (limite - topo).clamp(96.0, media.size.height * 0.6);
      if (_alturaMaxima == null || (nova - _alturaMaxima!).abs() > 1) {
        setState(() => _alturaMaxima = nova);
      }
    });
  }

  /// Métricas exatas do texto do campo (para o hit-test do quadradinho).
  /// Montado em `build` com a MESMA fonte do TextField (tema + fallback dos
  /// quadradinhos) para o hit-test bater com o que é renderizado.
  static const TextStyle _estiloTexto = TextStyle(fontSize: 14.5, height: 1.35);
  TextStyle? _estiloCampo;

  void _mudou(String novoTexto) {
    widget.nota.texto = novoTexto;
    // GRAVA NA HORA, a cada tecla — nada se perde ao fechar/trocar de tela.
    // (Arquivo pequeno; o custo de escrever por tecla é desprezível.)
    Storage.instance.salvar();
    // O debounce de 2s fica SÓ para a correção de maiúsculas — não para
    // salvar (ditado por voz não pode ser interrompido pela correção).
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      final corrigido = maiusculaAposItem(_ctrl.text);
      if (corrigido != _ctrl.text) {
        _ctrl.value = TextEditingValue(
          text: corrigido,
          selection: TextSelection.collapsed(offset: corrigido.length),
        );
        widget.nota.texto = corrigido;
        Storage.instance.salvar();
      }
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

  /// Índice da linha que contém o cursor (ou a última linha com conteúdo,
  /// se o cursor estiver depois de um "\n" final).
  int _linhaDoCursor(String texto, int cursor) {
    final linhas = texto.split('\n');
    var alvo = linhas.length - 1;
    var fim = 0;
    for (var i = 0; i < linhas.length; i++) {
      fim += linhas[i].length;
      if (cursor <= fim) {
        alvo = i;
        break;
      }
      fim += 1; // conta o "\n"
    }
    while (alvo > 0 && linhas[alvo].trim().isEmpty) {
      alvo--;
    }
    return alvo;
  }

  /// Alterna o número da linha do cursor: remove o "N- " se existir, ou
  /// adiciona o próximo número. Não insere linhas novas — quem cria linha é
  /// o Enter (que continua a numeração automaticamente).
  void _alternarNumero() {
    final texto = _ctrl.text;
    final linhas = texto.split('\n');
    final cursor = _ctrl.selection.isValid
        ? _ctrl.selection.baseOffset
        : texto.length;
    final alvo = _linhaDoCursor(texto, cursor);
    final linha = linhas[alvo];
    final m = RegExp(r'^\s*(\d+)\s*-\s*').firstMatch(linha);
    final bool adicionou;
    if (m != null) {
      linhas[alvo] = linha.substring(m.end);
      adicionou = false;
    } else {
      final anteriores = linhas.sublist(0, alvo).join('\n');
      final n = proximoNumeroLista(anteriores);
      linhas[alvo] = '$n- ${linha.trimLeft()}';
      adicionou = true;
    }
    final novo = linhas.join('\n');
    var pos = 0;
    for (var i = 0; i < alvo; i++) {
      pos += linhas[i].length + 1;
    }
    pos += linhas[alvo].length;
    _ctrl.value = TextEditingValue(
      text: novo,
      selection: TextSelection.collapsed(offset: pos),
    );
    _foco.requestFocus();
    _mudou(novo);
    setState(() => _numerado = adicionou);
  }

  /// Converte a LINHA DO CURSOR em item de to-do ("☐ "); se a linha já for
  /// um item de to-do, remove o quadradinho (alterna). Funciona em qualquer
  /// linha, não só no fim do texto.
  void _inserirTodo() {
    final texto = _ctrl.text;
    final linhas = texto.split('\n');
    final cursor = _ctrl.selection.isValid
        ? _ctrl.selection.baseOffset
        : texto.length;
    final alvo = _linhaDoCursor(texto, cursor);
    final linha = linhas[alvo];
    final limpo = linha.trimLeft();
    final inicioLimpo = linha.length - limpo.length;
    final ehTodo = limpo.startsWith('☐') || limpo.startsWith('☑');
    final String nova;
    if (ehTodo) {
      var fim = inicioLimpo + 1;
      if (fim < linha.length && linha.codeUnitAt(fim) == 0xFE0E) fim++;
      if (fim < linha.length && linha[fim] == ' ') fim++;
      nova = linha.substring(fim);
    } else {
      // \uFE0E força apresentação em TEXTO (sem virar emoji colorido).
      nova = '☐\uFE0E $limpo';
    }
    linhas[alvo] = nova;
    final novo = linhas.join('\n');
    var pos = 0;
    for (var i = 0; i < alvo; i++) {
      pos += linhas[i].length + 1;
    }
    pos += linhas[alvo].length;
    _ctrl.value = TextEditingValue(
      text: novo,
      selection: TextSelection.collapsed(offset: pos),
    );
    _foco.requestFocus();
    _mudou(novo);
    setState(() => _numerado = false);
  }

  /// Alterna o scroll interno do texto entre o topo e o pé.
  void _irAoExtremo() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 2) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _scroll.animateTo(pos.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  /// Ao tocar no quadradinho (☐/☑) de uma linha de to-do, alterna entre
  /// marcado e desmarcado. O toque em qualquer outro lugar segue normal.
  void _toqueTexto(Offset posicaoGlobal) {
    // Toque na caixinha re-ancora a visibilidade (cobre o caso de ela ter
    // sido rolada para trás do "+" enquanto já estava focada).
    _agendarAjuste();
    final texto = _ctrl.text;
    if (!texto.contains('☐') && !texto.contains('☑')) return;
    final ctx = _campoKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(posicaoGlobal);
    final dx = local.dx - 14;
    if (dx < 0 || dx > 40) return; // só na faixa dos quadradinhos
    final dy = local.dy + (_scroll.hasClients ? _scroll.offset : 0.0) - 2;
    if (dy < 0) return;
    final painter = TextPainter(
      text: TextSpan(text: texto, style: _estiloCampo ?? _estiloTexto),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: box.size.width - 28);
    final pos = painter.getPositionForOffset(
        Offset(dx.clamp(0.0, painter.width), dy));
    final offset = pos.offset.clamp(0, texto.length);
    var inicio = texto.lastIndexOf('\n', offset > 0 ? offset - 1 : 0);
    inicio = inicio < 0 ? 0 : inicio + 1;
    var fim = texto.indexOf('\n', offset);
    if (fim < 0) fim = texto.length;
    final linha = texto.substring(inicio, fim);
    final m = RegExp(r'^\s*(☐|☑)').firstMatch(linha);
    if (m == null) return;
    // Índice real do quadradinho = início da linha + deslocamento do grupo 1
    // dentro do match (m.start aponta para o começo do match inteiro, que
    // inclui os espaços casados pelo \s*).
    final idx = inicio + m.start + m.group(0)!.indexOf(m.group(1)!);
    final novoChar = texto[idx] == '☐' ? '☑' : '☐';
    // Sempre grava o quadradinho com \uFE0E (VS15) logo depois: se o texto
    // veio de um backup antigo (sem VS15), o ☑/☐ renderizaria como emoji
    // colorido em alguns celulares. Descarta um VS15 perdido que exista.
    var pos2 = idx + 1;
    if (pos2 < texto.length && texto.codeUnitAt(pos2) == 0xFE0E) pos2++;
    final novo = '${texto.substring(0, idx)}$novoChar'
        '\uFE0E'
        '${texto.substring(pos2)}';
    _ctrl.value = TextEditingValue(
      text: novo,
      selection:
          TextSelection.collapsed(offset: offset.clamp(0, novo.length)),
    );
    _mudou(novo);
  }

  /// Detecta o toque por eventos crus de ponteiro (o GestureDetector perde a
  /// disputa de gestos para o próprio campo de texto e nunca dispararia).
  Offset? _toqueInicial;
  DateTime? _toqueInicialT;

  void _pointerDown(PointerDownEvent e) {
    _toqueInicial = e.position;
    _toqueInicialT = DateTime.now();
  }

  void _pointerUp(PointerUpEvent e) {
    final ini = _toqueInicial;
    final iniT = _toqueInicialT;
    _toqueInicial = null;
    _toqueInicialT = null;
    if (ini == null || iniT == null) return;
    final moveu = (e.position - ini).distance;
    final rapido = DateTime.now().difference(iniT).inMilliseconds < 500;
    if (!moveu.isFinite || moveu > 8 || !rapido) return; // foi arrasto/seleção
    _toqueTexto(e.position);
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
      // Mantém o controlador do campo de comentário em sincronia (senão o
      // próximo flush sobrescreveria o título com texto antigo).
      _ctrlComentario.text = titulo!;
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
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.azul;
    final corFerramentas = app.barraFerramentas;
    final onBarra = ThemeData.estimateBrightnessForColor(corFerramentas) ==
            Brightness.dark
        ? Colors.white
        : Colors.black87;

    // Mesma fonte do tema + fallback com os glifos ☐/☑ em TEXTO (Noto Sans
    // Symbols 2, subset embutido): sem ele alguns celulares renderizam o ☑
    // como emoji verde. Também é o estilo usado pelo hit-test (_toqueTexto).
    _estiloCampo = TextStyle(
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
      fontFamilyFallback: const ['NotoSansSymbols2'],
      fontSize: 14.5,
      height: 1.35,
    );

    _comentarioVisivel = _comentarioExpandido ||
        (!widget.modoTarefas &&
            (widget.nota.comentario?.isNotEmpty ?? false));

    return Caixa3D(
      cor: app.notaInicio,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barra de ferramentas com cor separada (ou embutida na superfície
          // neumórfica, com linha interna sutil embaixo). No tema bege a
          // barra tem gradiente marrom próprio.
          Container(
            decoration: app.neumorfico
                ? BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(14)),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: app.barraFerramentas == app.notaInicio &&
                              app.barraFerramentas == app.notaFim
                          ? [app.notaInicio, app.notaFim]
                          : [app.barraFerramentas, app.barraFerramentasFim],
                    ),
                    border: const Border(
                      bottom: BorderSide(color: Color(0x2E000000)),
                    ),
                  )
                : BoxDecoration(
                    color: corFerramentas,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(14)),
                  ),
            padding: const EdgeInsets.fromLTRB(10, 4, 6, 2),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: widget.indice,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 22,
                    color: onBarra.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _BotaoMini(
                          icone: Icons.copy_all_outlined,
                          tooltip: 'Copiar',
                          onTap: widget.onCopiar,
                          cor: onBarra,
                        ),
                        _BotaoMini(
                          icone: widget.nota.concluida
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          tooltip: widget.nota.concluida
                              ? 'Desmarcar'
                              : 'Marcar como feito',
                          onTap: _alternarConcluida,
                          cor: onBarra,
                        ),
                        if (widget.modoTarefas)
                          _BotaoMini(
                            icone: _numerado
                                ? Icons.format_list_numbered
                                : Icons.format_align_justify,
                            tooltip: _numerado
                                ? 'Remover número da linha'
                                : 'Numerar linha',
                            onTap: _alternarNumero,
                            cor: onBarra,
                          ),
                        _BotaoMini(
                          icone: Icons.checklist,
                          tooltip: 'Item de to-do (☐)',
                          onTap: _inserirTodo,
                          cor: onBarra,
                        ),
                        _BotaoMini(
                          icone: widget.modoTarefas
                              ? Icons.arrow_downward
                              : Icons.arrow_upward,
                          tooltip: widget.modoTarefas
                              ? 'Mover para Futuro'
                              : 'Mover para Tarefas',
                          onTap: widget.onMover,
                          cor: onBarra,
                        ),
                        _BotaoMini(
                          icone: Icons.unfold_more,
                          tooltip: 'Topo / Pé',
                          onTap: _irAoExtremo,
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
                          onTap: () => setState(
                              () => _comentarioExpandido = !_comentarioExpandido),
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
                  ),
                ),
              ],
            ),
          ),
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _pointerDown,
            onPointerUp: _pointerUp,
            child: Scrollbar(
              controller: _scroll,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: _alturaMaxima == null
                      ? double.infinity
                      : (_alturaMaxima! - 40).clamp(60.0, double.infinity),
                ),
                child: TextField(
                  key: _campoKey,
                  scrollController: _scroll,
                  controller: _ctrl,
                  focusNode: _foco,
                  minLines: 1,
                  maxLines: 24,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: [LinhasNumeradas()],
                  style: (_estiloCampo ?? _estiloTexto).copyWith(
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
            ),
          ),
          // Subcaixinha de comentário inline (abaixo com letra mais fraca)
          if (_comentarioVisivel)
           Container(
              decoration: BoxDecoration(
                color: app.notaFim.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14)),
              ),
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
              child: TextField(
                controller: _ctrlComentario,
                onChanged: (v) {
                  widget.nota.comentario = v.isEmpty ? null : v;
                  Storage.instance.salvar();
                },
                minLines: 1,
                maxLines: 1,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Comentário…',
                ),
                style: TextStyle(
                  fontSize: 13,
                  fontFamilyFallback: const ['NotoSansSymbols2'],
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
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.azul;
    if (!app.neumorfico) {
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
    final corIcone = isDanger ? Colors.redAccent : (cor ?? Colors.white);
    // Botão segue o gradiente da barra quando ela tem cor própria (bege:
    // marrom); senão usa a superfície padrão do tema.
    final barraPropria = app.barraFerramentas != app.notaInicio ||
        app.barraFerramentas != app.notaFim;
    return BotaoNeum(
      raio: 9,
      padding: const EdgeInsets.all(5),
      corInicio: barraPropria ? app.barraFerramentas : null,
      corFim: barraPropria ? app.barraFerramentasFim : null,
      tooltip: tooltip,
      onTap: onTap,
      child: Icon(icone, size: 17, color: corIcone),
    );
  }
}