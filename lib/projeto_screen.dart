import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'barra_config.dart';
import 'caixa3d.dart';
import 'cores.dart';
import 'editor.dart';
import 'models.dart';
import 'ocr.dart';
import 'pdf_export.dart';
import 'storage.dart';
import 'tema.dart';

/// Página de um projeto dividida em duas abas: "Tarefas" (atuais) e "Ideias".
class ProjetoScreen extends StatefulWidget {
  const ProjetoScreen({
    super.key,
    required this.projeto,
    this.abaInicial = 0,
    this.termoInicial,
    this.notaAlvo,
  });

  final Projeto projeto;

  /// Aba em que a tela abre (0 = Tarefas, 1 = Ideias). Usado pela busca
  /// global da tela inicial para cair direto na aba certa.
  final int abaInicial;

  /// Termo de busca já aplicado ao abrir (deixa a busca da aba aberta e o
  /// texto destacado). Usado pela busca global.
  final String? termoInicial;

  /// Id da caixinha para a qual rolar automaticamente ao abrir (busca global).
  final String? notaAlvo;

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
    _tabCtrl = TabController(
        length: 2, vsync: this, initialIndex: widget.abaInicial.clamp(0, 1));
    // Vindo da busca global: já abre com a busca ativa (texto destacado) e
    // rola até a caixinha encontrada.
    final termo = widget.termoInicial?.trim() ?? '';
    if (termo.isNotEmpty) {
      _buscando = true;
      _ctrlBusca.text = termo;
    }
    if (widget.notaAlvo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _irParaNota(widget.notaAlvo!);
      });
    }
  }

  /// Rola a lista até a caixinha [id] ficar visível (com pequenas tentativas,
  /// caso ela ainda não tenha sido construída no primeiro quadro).
  void _irParaNota(String id, {int tentativa = 0}) {
    final ctx = _chaves[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.15,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (tentativa < 5) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _irParaNota(id, tentativa: tentativa + 1);
      });
    }
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

  void _adicionar(int aba, {String? comTexto}) {
    final nota = Nota(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      texto: comTexto ?? (aba == 0 ? '1- ' : ''),
    );
    setState(() => _lista(aba).add(nota));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chaveDa(nota.id).currentState?.focarNoFim();
    });
    _salvar();
  }

  /// Cria uma caixinha nova já com o texto extraído de uma imagem (OCR) —
  /// acessível pelo toque LONGO no botão "+".
  Future<void> _adicionarDeImagem() async {
    final texto = await extrairTextoDeImagem();
    if (!mounted) return;
    if (texto == null) {
      mostrarAviso(context, 'Nenhum texto encontrado na imagem');
      return;
    }
    _adicionar(_tabCtrl.index, comTexto: texto);
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

  /// Move a caixinha para a OUTRA aba (Tarefas <-> Ideias), com desfazer.
  void _moverOutraAba(int aba, int i) {
    final nota = _lista(aba).removeAt(i);
    final destino = aba == 0 ? widget.projeto.futuro : widget.projeto.tarefas;
    destino.add(nota);
    final nomeDestino = aba == 0 ? 'Ideias' : 'Tarefas';
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

  /// Excluir o projeto de DENTRO dele: confirma e devolve 'excluir' para a tela
  /// inicial, que faz a remoção segura (com Desfazer). Assim a exclusão passa
  /// SEMPRE pelo caminho protegido único da home (guarda anti-esvaziamento).
  Future<void> _excluirProjeto() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir projeto?'),
        content: Text(
            '"${widget.projeto.nome}" e todas as suas caixas serão apagados.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context, 'excluir');
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
      buf.writeln('  --- Ideias ---');
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
                      : 'Buscar em Ideias…',
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
                  padding: EdgeInsets.fromLTRB(
                      16, 4, 16, temaController.compacto ? 110 : 150),
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
                    padding: EdgeInsets.only(
                        bottom: temaController.compacto ? 5 : 10),
                    child: _CaixaNota(
                      key: _chaveDa(filtradas[i].id),
                      projeto: widget.projeto,
                      nota: filtradas[i],
                      indice: _lista(aba).indexOf(filtradas[i]),
                      modoTarefas: ehTarefas,
                      termoBusca: q,
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
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Excluir projeto',
              onPressed: _excluirProjeto,
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
                    Tab(text: 'Ideias'),
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
      floatingActionButton: GestureDetector(
        // Toque longo no "+": nova caixinha a partir de imagem (OCR).
        onLongPress: _adicionarDeImagem,
        child: FloatingActionButton(
          onPressed: () => _adicionar(_tabCtrl.index),
          tooltip: 'Nova caixa de texto',
          child: const Icon(Icons.add),
        ),
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
    required this.projeto,
    required this.nota,
    required this.indice,
    required this.modoTarefas,
    required this.onCopiar,
    required this.onExcluir,
    required this.onMover,
    this.termoBusca = '',
  });

  /// Projeto a que a caixinha pertence — usado para marcar o projeto como
  /// "em andamento" quando uma caixinha é marcada como feita.
  final Projeto projeto;
  final Nota nota;
  final int indice;

  /// Se false (modo Ideias), não mostra botão de lista numerada nem inicia
  /// novas caixinhas com "1- ".
  final bool modoTarefas;

  /// Termo ativo da busca na aba — as ocorrências no texto são grifadas.
  final String termoBusca;

  final VoidCallback onCopiar;
  final VoidCallback onExcluir;

  /// Move a caixinha para a outra aba (Tarefas <-> Ideias).
  final VoidCallback onMover;

  @override
  State<_CaixaNota> createState() => _CaixaNotaState();
}

class _CaixaNotaState extends State<_CaixaNota> with WidgetsBindingObserver {
  late final BuscaController _ctrl;
  late final TextEditingController _ctrlComentario;
  final HistoricoTexto _historico = HistoricoTexto();
  final FocusNode _foco = FocusNode();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _campoKey = GlobalKey();
  Timer? _debounce;
  bool _tinhaFocoAoParar = false;
  // Última altura do teclado (viewInsets.bottom) que vimos — usado para
  // detectar o instante em que o teclado FECHA (>0 → 0) e soltar o foco.
  double _insetBottomAnterior = 0;
  bool _numerado = true;
  bool _comentarioExpandido = false;
  bool _comentarioVisivel = false;

  @override
  void initState() {
    super.initState();
    _ctrl = BuscaController(text: widget.nota.texto);
    _historico.comecar(widget.nota.texto);
    _ctrlComentario =
        TextEditingController(text: widget.nota.comentario ?? '');
    _foco.addListener(_aoMudarFoco);
    WidgetsBinding.instance.addObserver(this);
    // Links antigos (migrados sem título) e links de vídeos novos ganham o
    // título do YouTube automaticamente — sem precisar abrir o diálogo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _buscarTitulosPendentes();
    });
  }

  /// Reabre o teclado ao VOLTAR de outro app. O Android, ao sair, esconde o
  /// teclado e NÃO o reabre sozinho — mesmo que o foco continue na caixinha —
  /// então não dava para continuar digitando (bug intermitente, pior nas
  /// trocas rápidas). Guardamos que a caixinha estava sendo editada ao sair
  /// (`_tinhaFocoAoParar`) e, ao voltar, recriamos a conexão de entrada.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_foco.hasFocus) _tinhaFocoAoParar = true;
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    if (!_tinhaFocoAoParar) return;
    _tinhaFocoAoParar = false;
    // Reabre o teclado ao voltar. O ATRASO é essencial: logo no resume a
    // janela ainda não recuperou o foco do sistema e o pedido de teclado seria
    // ignorado. A 2ª tentativa só dispara se a 1ª NÃO reabriu (resume lento) —
    // pedir duas vezes causava o efeito "sobe e desce". O texto e o cursor
    // ficam intactos (o controlador preserva a seleção).
    _reabrirTeclado(220);
    _reabrirTeclado(520, somenteSeFechado: true);
  }

  void _reabrirTeclado(int ms, {bool somenteSeFechado = false}) {
    Future.delayed(Duration(milliseconds: ms), () {
      if (!mounted) return;
      // Se o teclado já reabriu (1ª tentativa pegou), não pede de novo.
      if (somenteSeFechado && View.of(context).viewInsets.bottom > 0) return;
      // Solta e repede o foco no MESMO instante para recriar a conexão de IME:
      // um requestFocus num nó que ainda "tem" foco é no-op e o teclado não
      // reabriria. Feito atomicamente aqui, sem o teclado ficar séculos para
      // baixo entre as duas chamadas.
      _foco.unfocus();
      _foco.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  /// Solta o foco quando o usuário ESCONDE o teclado (setinha para baixo) com
  /// o app em primeiro plano. O Android some com o teclado mas o Flutter
  /// mantém o foco na caixinha — e um campo focado REABRE a conexão de teclado
  /// no frame seguinte, fazendo o teclado "voltar a subir" (era o bug de ter de
  /// minimizar 2-3× com o cursor no fim). Por isso soltamos o foco IMEDIATAMENTE
  /// ao detectar o teclado fechando (altura >0 → 0): sem foco, nada reabre.
  ///
  /// ⚠️ V0.1.63: era um `unfocus` com DEBOUNCE de 320ms; mas o teclado reabria
  /// dentro da folga e o `bottom>0` cancelava o unfocus → nunca soltava. Voltou
  /// a ser imediato. Para não fechar o teclado numa troca de layout transitória
  /// (emoji/símbolos), só solta quando NÃO há composição IME ativa (fora do
  /// meio de uma palavra).
  ///
  /// ⚠️ Só age com o app `resumed` — ao SAIR para outro app o teclado também
  /// fecha, mas aí queremos PRESERVAR o foco para reabri-lo ao voltar
  /// (`didChangeAppLifecycleState`/`_reabrirTeclado`).
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final bottom = View.of(context).viewInsets.bottom;
    final fechou = _insetBottomAnterior > 0 && bottom == 0;
    _insetBottomAnterior = bottom;
    if (!fechou) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    if (!_foco.hasFocus) return;
    // Composição IME ativa = usuário no meio de uma palavra → o "0" é provável
    // troca de layout (transitório); não solta o foco.
    if (!_ctrl.value.composing.isCollapsed) return;
    // Mata a correção de maiúscula pendente (senão ela reabriria o teclado).
    _debounce?.cancel();
    _foco.unfocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _foco.removeListener(_aoMudarFoco);
    // Derrama o que está nos controladores direto no modelo e no disco —
    // cobre o texto que a IME ainda não tinha confirmado (composição) quando
    // o usuário sai rápido da tela.
    _guardarTudo();
    WidgetsBinding.instance.removeObserver(this);
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

  /// Reage à mudança de foco da caixinha.
  /// - Ao GANHAR foco: semeia o rastreio da altura do teclado com o valor
  ///   atual. Assim, se o teclado JÁ estava aberto (troca entre caixinhas), o
  ///   próximo fechamento é detectado corretamente por [didChangeMetrics].
  /// - Ao PERDER foco (toque em outra caixinha, voltar de tela, teclado
  ///   fechando): derrama o texto na hora — é o sinal mais cedo de que o
  ///   usuário parou de digitar e nada pode ficar só no teclado.
  void _aoMudarFoco() {
    if (_foco.hasFocus) {
      if (mounted) _insetBottomAnterior = View.of(context).viewInsets.bottom;
      return;
    }
    _guardarTudo();
  }

  void focarNoFim() {
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    _foco.requestFocus();
  }

  /// Métricas exatas do texto do campo (para o hit-test do quadradinho).
  /// Montado em `build` com a MESMA fonte do TextField (tema + fallback dos
  /// quadradinhos) para o hit-test bater com o que é renderizado.
  static const TextStyle _estiloTexto = TextStyle(fontSize: 14.5, height: 1.35);
  TextStyle? _estiloCampo;

  void _mudou(String novoTexto) {
    _historico.registrar(novoTexto);
    widget.nota.texto = novoTexto;
    // GRAVA NA HORA, a cada tecla — nada se perde ao fechar/trocar de tela.
    // (Arquivo pequeno; o custo de escrever por tecla é desprezível.)
    Storage.instance.salvar();
    // O debounce de 2s fica SÓ para a correção de maiúsculas — não para
    // salvar (ditado por voz não pode ser interrompido pela correção).
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      // ⚠️ NÃO corrigir se o teclado já foi escondido: mexer no `_ctrl.value`
      // com o campo AINDA focado REABRE o teclado — era o motivo de, às vezes,
      // ter de "minimizar o teclado duas vezes" (a correção disparava dentro
      // da janela em que o campo ainda tinha foco após esconder). Só corrige
      // com o teclado à vista.
      if (!mounted || !_foco.hasFocus) return;
      if (View.of(context).viewInsets.bottom == 0) return;
      final corrigido = maiusculaAposItem(_ctrl.text);
      if (corrigido != _ctrl.text) {
        _ctrl.value = TextEditingValue(
          text: corrigido,
          selection: TextSelection.collapsed(offset: corrigido.length),
        );
        widget.nota.texto = corrigido;
        // Alinha o histórico sem criar um passo de desfazer (a correção não
        // passou por _mudou/registrar).
        _historico.sincronizar(corrigido);
        Storage.instance.salvar();
      }
    });
  }

  void _limpar() {
    _ctrl.clear();
    _mudou('');
  }

  /// Restaura o último texto apagado/alterado — cobre também as ações da
  /// barra (centralizar, numerar, item de to-do).
  void _desfazer() {
    final restaurado = _historico.desfazer();
    if (restaurado == null) return;
    setState(() {});
    _ctrl.value = TextEditingValue(
      text: restaurado,
      selection: TextSelection.collapsed(offset: restaurado.length),
    );
    _mudou(restaurado);
  }

  void _alternarConcluida() {
    setState(() {
      widget.nota.concluida = !widget.nota.concluida;
      // ESPELHA o estado no projeto: marcar a caixinha como feita → projeto
      // "em andamento"; DESMARCAR → projeto deixa de estar em andamento.
      widget.projeto.emAndamento = widget.nota.concluida;
    });
    Storage.instance.salvar();
  }

  /// Centraliza a LINHA que contém a seleção: insere espaços no início
  /// calculados pela largura real do texto (o TextField não suporta
  /// alinhamento por linha). A palavra/frase fica centralizada NA MESMA
  /// linha, sem sair do texto. Desfazer (undo) reverte.
  void _centralizarLinha() {
    final sel = _ctrl.selection;
    if (!sel.isValid || sel.isCollapsed) {
      mostrarAviso(context, 'Selecione uma palavra ou frase para centralizar');
      return;
    }
    final texto = _ctrl.text;
    var inicio = texto.lastIndexOf('\n', sel.start > 0 ? sel.start - 1 : 0);
    inicio = inicio < 0 ? 0 : inicio + 1;
    var fim = texto.indexOf('\n', sel.start);
    if (fim < 0) fim = texto.length;
    final limpa = texto.substring(inicio, fim).trim();
    if (limpa.isEmpty) {
      mostrarAviso(context, 'Selecione uma palavra ou frase para centralizar');
      return;
    }
    final box = _campoKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final maxWidth = box.size.width - 28;
    final estilo = _estiloCampo ?? _estiloTexto;
    final scaler = MediaQuery.textScalerOf(context);
    final pLinha = TextPainter(
      text: TextSpan(text: limpa, style: estilo),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout(maxWidth: maxWidth);
    if (pLinha.width > maxWidth - 40) {
      mostrarAviso(context, 'Linha muito longa para centralizar');
      return;
    }
    final pEspaco = TextPainter(
      text: TextSpan(text: ' ', style: estilo),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final espacos =
        ((maxWidth - pLinha.width) / 2 / pEspaco.width).floor().clamp(0, 60);
    final novaLinha = ' ' * espacos + limpa;
    _historico.empilhar(texto);
    _historico.suprimir();
    final novo = texto.replaceRange(inicio, fim, novaLinha);
    _ctrl.value = TextEditingValue(
      text: novo,
      selection: TextSelection.collapsed(offset: inicio + novaLinha.length),
    );
    _mudou(novo);
    _historico.reativar();
    setState(() {});
  }

  /// Índice da linha que contém o cursor.
  ///
  /// ⚠️ Fica EXATAMENTE na linha do cursor, mesmo que ela esteja vazia — antes
  /// havia um "recuo" que voltava para a última linha COM conteúdo quando a
  /// linha do cursor era vazia; isso quebrava criar um to-do (ou numerar) numa
  /// segunda linha em branco: o marcador ia parar na primeira linha. (Bug #2.)
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
    return alvo;
  }

  /// Alterna o número da linha do cursor: remove o "N- " se existir, ou
  /// adiciona o próximo número. Não insere linhas novas — quem cria linha é
  /// o Enter (que continua a numeração automaticamente).
  void _alternarNumero() {
    _historico.empilhar(_ctrl.text);
    _historico.suprimir();
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
    _historico.reativar();
    setState(() => _numerado = adicionou);
  }

  /// Converte a LINHA DO CURSOR em item de to-do ("☐ "); se a linha já for
  /// um item de to-do, remove o quadradinho (alterna). Funciona em qualquer
  /// linha, não só no fim do texto.
  void _inserirTodo() {
    _historico.empilhar(_ctrl.text);
    _historico.suprimir();
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
    _historico.reativar();
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
    final links = await showDialog<List<NotaLink>>(
      context: context,
      builder: (_) => _DialogoLinks(links: widget.nota.links),
    );
    if (links == null) return;
    widget.nota.links = links;
    Storage.instance.salvar();
    // Links de YouTube sem título (digitados e salvos antes do debounce
    // buscar) ganham o título agora.
    _buscarTitulosPendentes();
  }

  /// Lê o texto de uma imagem (OCR) e INSERE na caixinha na posição do
  /// cursor — o desfazer (undo) reverte a inserção.
  Future<void> _lerImagem() async {
    final texto = await extrairTextoDeImagem();
    if (!mounted) return;
    if (texto == null) {
      mostrarAviso(context, 'Nenhum texto encontrado na imagem');
      return;
    }
    final atual = _ctrl.text;
    final pos = _ctrl.selection.isValid
        ? _ctrl.selection.baseOffset
        : atual.length;
    // Se o cursor está no fim e o texto não termina em quebra, abre linha.
    final prefixo = (pos == atual.length && atual.isNotEmpty)
        ? (atual.endsWith('\n') ? '' : '\n')
        : '';
    final novo = atual.replaceRange(pos, pos, '$prefixo$texto');
    _historico.empilhar(atual);
    _ctrl.value = TextEditingValue(
      text: novo,
      selection: TextSelection.collapsed(offset: novo.length),
    );
    _mudou(novo);
    setState(() {});
  }

  /// Busca (via oEmbed) o título dos links de YouTube que ainda não têm
  /// título e salva — aparecem nos comentários sem precisar clicar em nada.
  /// Nunca lança: um erro aqui não pode derrubar o app.
  Future<void> _buscarTitulosPendentes() async {
    try {
      final links = widget.nota.links;
      for (var i = 0; i < links.length; i++) {
        final l = links[i];
        if (l.titulo != null) continue;
        final url = l.url.trim();
        if (!url.contains('youtube.com') && !url.contains('youtu.be')) {
          continue;
        }
        final t = await _tituloYouTube(url);
        if (!mounted) return;
        if (t != null) {
          setState(() => l.titulo = t);
          Storage.instance.salvar();
        }
      }
    } catch (_) {
      // silencioso — título continua pendente para a próxima tentativa
    }
  }

  Future<String?> _tituloYouTube(String url) async {
    // NUNCA lança: URL inválida ou falha de rede apenas devolvem null —
    // exceção aqui derruba o app (tela branca).
    try {
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
    } catch (_) {
      return null;
    }
  }

  /// Constrói o botão da barra para a ferramenta [f] (ou null quando ela não
  /// se aplica — ex.: "numerar" só existe na aba Tarefas). A ordem dos botões
  /// é decidida pelo [barraController]; este método só sabe DESENHAR cada um.
  Widget? _botaoFerramenta(Ferramenta f, Color onBarra) {
    switch (f) {
      case Ferramenta.copiar:
        return _BotaoMini(
          icone: Icons.copy_all_outlined,
          tooltip: 'Copiar',
          onTap: widget.onCopiar,
          cor: onBarra,
        );
      case Ferramenta.desfazer:
        return _BotaoMini(
          icone: Icons.undo,
          tooltip: 'Desfazer apagar',
          onTap: _desfazer,
          cor: onBarra,
        );
      case Ferramenta.feito:
        return _BotaoMini(
          icone: widget.nota.concluida
              ? Icons.check_box
              : Icons.check_box_outline_blank,
          tooltip: widget.nota.concluida ? 'Desmarcar' : 'Marcar como feito',
          onTap: _alternarConcluida,
          cor: onBarra,
        );
      case Ferramenta.numerar:
        if (!widget.modoTarefas) return null;
        return _BotaoMini(
          icone: _numerado
              ? Icons.format_list_numbered
              : Icons.format_align_justify,
          tooltip: _numerado ? 'Remover número da linha' : 'Numerar linha',
          onTap: _alternarNumero,
          cor: onBarra,
        );
      case Ferramenta.todo:
        return _BotaoMini(
          icone: Icons.checklist,
          tooltip: 'Item de to-do (☐)',
          onTap: _inserirTodo,
          cor: onBarra,
        );
      case Ferramenta.mover:
        return _BotaoMini(
          icone: widget.modoTarefas
              ? Icons.arrow_downward
              : Icons.arrow_upward,
          tooltip: widget.modoTarefas
              ? 'Mover para Ideias'
              : 'Mover para Tarefas',
          onTap: widget.onMover,
          cor: onBarra,
        );
      case Ferramenta.extremo:
        return _BotaoMini(
          icone: Icons.unfold_more,
          tooltip: 'Topo / Pé',
          onTap: _irAoExtremo,
          cor: onBarra,
        );
      case Ferramenta.link:
        return _BotaoMini(
          icone: Icons.add_link,
          tooltip: 'Link',
          onTap: _abrirLink,
          cor: onBarra,
        );
      case Ferramenta.imagem:
        return _BotaoMini(
          icone: Icons.image_outlined,
          tooltip: 'Ler texto de imagem (OCR)',
          onTap: _lerImagem,
          cor: onBarra,
        );
      case Ferramenta.comentario:
        return _BotaoMini(
          icone: _comentarioExpandido
              ? Icons.chat_bubble
              : Icons.chat_bubble_outline,
          tooltip: 'Comentário',
          onTap: () =>
              setState(() => _comentarioExpandido = !_comentarioExpandido),
          cor: onBarra,
        );
      case Ferramenta.editar:
        return _BotaoMini(
          icone: Icons.edit_outlined,
          tooltip: 'Editar',
          onTap: focarNoFim,
          cor: onBarra,
        );
      case Ferramenta.centralizar:
        return _BotaoMini(
          icone: Icons.format_align_center,
          tooltip: 'Centralizar linha (seleção)',
          onTap: _centralizarLinha,
          cor: onBarra,
        );
      case Ferramenta.limpar:
        return _BotaoMini(
          icone: Icons.cleaning_services,
          tooltip: 'Limpar conteúdo',
          onTap: _limpar,
          cor: onBarra,
        );
      case Ferramenta.excluir:
        return _BotaoMini(
          icone: Icons.delete_outline,
          tooltip: 'Excluir',
          isDanger: true,
          onTap: widget.onExcluir,
          cor: onBarra,
        );
    }
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

    // Destaque da busca: o próprio controlador pinta o fundo amarelo nas
    // ocorrências (dentro do layout do texto) — sempre alinhado.
    _ctrl.termo = widget.termoBusca.trim();

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
                    // A ORDEM dos botões vem do barraController (configurável
                    // em Configurações → "Ordem dos botões da barra"); a barra
                    // se reconstrói ao mudar a ordem.
                    child: ListenableBuilder(
                      listenable: barraController,
                      builder: (context, _) {
                        final botoes = <Widget>[];
                        for (final f in barraController.ordem) {
                          final b = _botaoFerramenta(f, onBarra);
                          if (b != null) botoes.add(b);
                        }
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: botoes,
                        );
                      },
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
                // Mantém o cursor sempre visível ACIMA do teclado e do botão
                // "+" enquanto se digita: ao mover o cursor, o Flutter rola a
                // PÁGINA para deixá-lo a esta distância da borda inferior.
                // 108 = altura do FAB (56) + margem (16) + folga. É o
                // mecanismo nativo que substituiu a trava de altura por timers.
                scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 108),
                style: (_estiloCampo ?? _estiloTexto).copyWith(
                  color: widget.nota.concluida
                      ? Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.45)
                      : Theme.of(context).colorScheme.onSurface,
                ),
                contextMenuBuilder: _menuSelecao,
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
          // Subcaixinha inline: títulos dos links (SEMPRE visíveis quando há
          // links — ex.: título do vídeo do YouTube) + comentário manual.
          if (widget.nota.links.isNotEmpty || _comentarioVisivel)
            Container(
              decoration: BoxDecoration(
                color: app.notaFim.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14)),
              ),
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final l in widget.nota.links)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            (l.titulo != null && l.url.contains('youtube'))
                                ? Icons.play_circle_outline
                                : Icons.link,
                            size: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.55),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l.titulo ?? l.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_comentarioVisivel)
                    TextField(
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
                ],
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

/// Diálogo de links da caixinha: até 3 links, cada um com campo próprio.
/// Ao colar URL do YouTube, busca o título via oEmbed (debounce 600ms) e o
/// mostra embaixo do campo — o título é salvo junto com o link.
class _DialogoLinks extends StatefulWidget {
  const _DialogoLinks({required this.links});

  final List<NotaLink> links;

  @override
  State<_DialogoLinks> createState() => _DialogoLinksState();
}

class _DialogoLinksState extends State<_DialogoLinks> {
  static const _max = 3;

  late final List<TextEditingController> _ctrls;
  late final List<String?> _titulos;
  late final List<bool> _buscando;
  late final List<Timer?> _debounces;

  @override
  void initState() {
    super.initState();
    _ctrls = widget.links
        .map((l) => TextEditingController(text: l.url))
        .toList();
    _titulos = widget.links.map((l) => l.titulo).toList();
    // growable: true é OBRIGATÓRIO — _adicionar/_remover fazem add/removeAt
    // (List.filled padrão é de tamanho fixo e estouraria com UnsupportedError,
    // derrubando o app na tela branca).
    _buscando = List.filled(_ctrls.length, false, growable: true);
    _debounces = List.filled(_ctrls.length, null, growable: true);
    if (_ctrls.isEmpty) {
      _ctrls.add(TextEditingController());
      _titulos.add(null);
      _buscando.add(false);
      _debounces.add(null);
    }
  }

  @override
  void dispose() {
    for (final t in _debounces) {
      t?.cancel();
    }
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _remover(int i) {
    setState(() {
      _debounces.removeAt(i)?.cancel();
      _ctrls.removeAt(i).dispose();
      _titulos.removeAt(i);
      _buscando.removeAt(i);
    });
  }

  void _adicionar() {
    if (_ctrls.length >= _max) return;
    setState(() {
      _ctrls.add(TextEditingController());
      _titulos.add(null);
      _buscando.add(false);
      _debounces.add(null);
    });
  }

  void _buscarTitulo(int i, String url) {
    _debounces[i]?.cancel();
    if (!url.contains('youtube.com') && !url.contains('youtu.be')) {
      setState(() {
        _titulos[i] = null;
        _buscando[i] = false;
      });
      return;
    }
    setState(() => _buscando[i] = true);
    _debounces[i] = Timer(const Duration(milliseconds: 600), () async {
      try {
        final t = await _tituloYouTube(url);
        if (mounted) {
          setState(() {
            _titulos[i] = t;
            _buscando[i] = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _buscando[i] = false);
      }
    });
  }

  /// Cola a URL da área de transferência no 1º campo vazio (ou no 1º campo).
  Future<void> _colar() async {
    final dados = await Clipboard.getData(Clipboard.kTextPlain);
    final texto = dados?.text?.trim() ?? '';
    if (!mounted) return;
    if (texto.isEmpty) {
      mostrarAviso(context, 'A área de transferência está vazia.');
      return;
    }
    var alvo = _ctrls.indexWhere((c) => c.text.trim().isEmpty);
    if (alvo < 0) alvo = 0;
    setState(() => _ctrls[alvo].text = texto);
    _buscarTitulo(alvo, texto);
  }

  /// Apaga todos os campos de link do diálogo.
  void _limpar() {
    setState(() {
      for (var i = 0; i < _ctrls.length; i++) {
        _debounces[i]?.cancel();
        _ctrls[i].clear();
        _titulos[i] = null;
        _buscando[i] = false;
      }
    });
  }

  Future<String?> _tituloYouTube(String url) async {
    // NUNCA lança (mesmo motivo do _CaixaNotaState): URL inválida ou falha
    // de rede devolvem null.
    try {
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
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textoForte = Theme.of(context)
        .colorScheme
        .onSurface
        .withValues(alpha: 0.65);
    return AlertDialog(
      title: const Text('Links'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _ctrls.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrls[i],
                      autofocus: i == 0 && _ctrls.length == 1,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        hintText: 'https://… (link ${i + 1})',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => _buscarTitulo(i, v.trim()),
                    ),
                  ),
                  if (_ctrls.length > 1)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Remover link',
                      onPressed: () => _remover(i),
                    ),
                ],
              ),
              if (_buscando[i])
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              if (_titulos[i] != null && !_buscando[i])
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _titulos[i]!,
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 13,
                        color: textoForte,
                      ),
                    ),
                  ),
                ),
            ],
            if (_ctrls.length < _max)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add_link, size: 18),
                  label: Text('Adicionar link (${_ctrls.length}/$_max)'),
                  onPressed: _adicionar,
                ),
              ),
          ],
        ),
      ),
      actions: [
        // Linha 1: Colar · Limpar · Fechar. Linha 2 (alinhada à direita,
        // embaixo de "Fechar"): Salvar.
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: _colar,
                  child: const Text('Colar'),
                ),
                const SizedBox(width: 2),
                TextButton(
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: _limpar,
                  child: const Text('Limpar'),
                ),
                const SizedBox(width: 2),
                TextButton(
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            FilledButton(
              style:
                  FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () {
                final links = <NotaLink>[
                  for (var i = 0; i < _ctrls.length; i++)
                    if (_ctrls[i].text.trim().isNotEmpty)
                      NotaLink(
                        url: _ctrls[i].text.trim(),
                        titulo: _titulos[i],
                      ),
                ];
                Navigator.pop(context, links);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ],
    );
  }
}
/// Menu de seleção (recortar/copiar/colar/selecionar tudo). Usa o
/// posicionamento PADRÃO do Flutter, que abre ACIMA da seleção quando cabe.
///
/// Antes ele era forçado para BAIXO (para não cobrir a barra da caixinha),
/// mas abaixo da seleção o menu ficava em cima das ALÇAS de arrastar — não
/// dava para estender a seleção para várias palavras. Acima da seleção as
/// alças (que ficam abaixo do texto) ficam livres. O `AdaptiveTextSelection
/// Toolbar.editableText` já resolve rótulos (Copiar/Colar/…) e a posição.
Widget _menuSelecao(
    BuildContext context, EditableTextState editableTextState) {
  return AdaptiveTextSelectionToolbar.editableText(
    editableTextState: editableTextState,
  );
}
