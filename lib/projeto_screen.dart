import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'barra_config.dart';
import 'caixa3d.dart';
import 'chat/chat_config.dart';
import 'cores.dart';
import 'muse_blob.dart';
import 'nav_bus.dart';
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
    this.adicionarAoAbrir = false,
    this.modoPastasInicial = false,
    this.embutido = false,
    this.onVoltarNaRaiz,
    this.onNaGradeMudou,
  });

  /// Abre já no modo PASTAS (ex.: projeto "Estudos").
  final bool modoPastasInicial;

  /// EMBUTIDO numa aba do shell (ex.: aba "Estudos"): a tela NUNCA sai da rota
  /// (não há rota para popar — ela vive no corpo do shell). O voltar do sistema,
  /// dentro de uma pasta, retorna à grade; já na grade, chama [onVoltarNaRaiz]
  /// (o shell troca para a aba Projetos). O botão "Excluir" some (projeto
  /// reservado não se apaga daqui).
  final bool embutido;

  /// Chamado quando o voltar do sistema é acionado já na raiz (grade) de uma
  /// tela embutida — o shell usa para trocar de aba em vez de sair do app.
  final VoidCallback? onVoltarNaRaiz;

  /// Avisado com `true` sempre que a tela volta À GRADE (raiz) e com `false`
  /// ao entrar numa pasta — o shell usa para saber se o voltar do sistema
  /// deve trocar de aba (só na raiz) ou deixar a tela tratar dentro.
  final ValueChanged<bool>? onNaGradeMudou;

  final Projeto projeto;

  /// Ao abrir, já cria uma caixinha nova em Tarefas e foca nela. Usado pelo
  /// App Shortcut "Nova nota" (anotar sem passar pela tela inicial).
  final bool adicionarAoAbrir;

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
  // Um ScrollController por aba (Tarefas/Ideias): a lista é lazy e cada aba do
  // TabBarView tem a sua — um controller único daria conflito de anexação.
  final Map<int, ScrollController> _scrollAbas = {};
  ScrollController _scrollDaAba(int aba) =>
      _scrollAbas.putIfAbsent(aba, () => ScrollController());
  late TabController _tabCtrl;
  final TextEditingController _ctrlBusca = TextEditingController();
  final FocusNode _focoBusca = FocusNode();
  bool _buscando = false;
  late bool _modoPastas = widget.modoPastasInicial;
  // Saída real da rota (ex.: projeto excluído): o PopScope abaixo veta o 1º
  // voltar dentro de uma pasta p/ retornar À GRADE — este flag libera o pop.
  bool _saindo = false;

  // Id da caixinha em edição (última a ganhar foco). A barra única de
  // ferramentas (acima do teclado) opera sobre ela. Não limpamos ao perder o
  // foco: se o teclado reabrir p/ a mesma caixinha, a barra reaparece pronta.
  String? _idBlocoAtivo;

  /// Estado da caixinha atualmente em edição (ou null se nenhuma está montada).
  _CaixaNotaState? get _blocoAtivo =>
      _idBlocoAtivo == null ? null : _chaves[_idBlocoAtivo]?.currentState;

  int get _qtdAbas => widget.projeto.qtdAbas;
  String _nomeAba(int i) => widget.projeto.nomeAba(i);

  void _recriarTabController([int? novoIndice]) {
    final idx = (novoIndice ?? _tabCtrl.index).clamp(0, _qtdAbas - 1);
    _tabCtrl.dispose();
    _tabCtrl = TabController(length: _qtdAbas, vsync: this, initialIndex: idx);
  }

  Future<void> _renomearAba(int aba) async {
    final atual = _nomeAba(aba);
    final ctrl = TextEditingController(text: atual);
    final novo = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Renomear aba'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: atual),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: Text('Salvar')),
        ],
      ),
    );
    if (novo == null) return;
    final t = novo.trim();
    if (t.isEmpty || t == atual) return;
    setState(() {
      if (aba == 0) widget.projeto.nomeTarefas = t;
      else if (aba == 1) widget.projeto.nomeFuturo = t;
      else widget.projeto.abasExtras[aba - 2].nome = t;
    });
    await _salvar();
  }

  Future<void> _criarNovaAba() async {
    final ctrl = TextEditingController(text: 'Nova aba ${widget.projeto.abasExtras.length + 1}');
    final nome = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Nova aba'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: 'Nome da aba'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: Text('Criar')),
        ],
      ),
    );
    if (nome == null) return;
    final t = nome.trim();
    if (t.isEmpty) return;
    final aba = AbaExtra(id: DateTime.now().microsecondsSinceEpoch.toString(), nome: t);
    setState(() => widget.projeto.abasExtras.add(aba));
    _recriarTabController(_qtdAbas - 1);
    await _salvar();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Aba "$t" criada')));
    }
  }

  void _mostrarSheetAbas() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.tab_rounded, size: 18, color: Theme.of(ctx).colorScheme.primary),
                SizedBox(width: 8),
                Text('Abas deste projeto', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
              SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (var i = 0; i < _qtdAbas; i++)
                      ListTile(
                        dense: true,
                        leading: Icon(i == 0 ? Icons.checklist_rounded : i == 1 ? Icons.lightbulb_outline : Icons.folder_outlined, size: 20),
                        title: Text(_nomeAba(i), style: TextStyle(fontWeight: _tabCtrl.index == i ? FontWeight.w700 : FontWeight.w500)),
                        selected: _tabCtrl.index == i,
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: Icon(Icons.edit_outlined, size: 18), tooltip: 'Renomear', onPressed: () { Navigator.pop(ctx); _renomearAba(i); }),
                          if (i >= 2)
                            IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.redAccent), tooltip: 'Excluir aba', onPressed: () async {
                              final ok = await showDialog<bool>(context: ctx, builder: (_) => AlertDialog(title: Text('Excluir aba?'), content: Text('Aba "${_nomeAba(i)}" e suas caixinhas serão apagadas.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancelar')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Excluir', style: TextStyle(color: Colors.red)))]));
                              if (ok != true) return;
                              Navigator.pop(ctx);
                              final estava = _tabCtrl.index;
                              setState(() => widget.projeto.abasExtras.removeAt(i - 2));
                              final novoIdx = estava >= _qtdAbas ? _qtdAbas - 1 : estava;
                              _recriarTabController(novoIdx);
                              await _salvar();
                            }),
                        ]),
                        onTap: () { Navigator.pop(ctx); _tabCtrl.animateTo(i); },
                      ),
                    Divider(),
                    ListTile(
                      leading: Icon(Icons.add, color: Theme.of(ctx).colorScheme.primary),
                      title: Text('Criar nova aba', style: TextStyle(color: Theme.of(ctx).colorScheme.primary, fontWeight: FontWeight.w600)),
                      onTap: () { Navigator.pop(ctx); _criarNovaAba(); },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
        length: _qtdAbas, vsync: this, initialIndex: widget.abaInicial.clamp(0, _qtdAbas - 1));
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
    if (widget.adicionarAoAbrir) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _adicionar(0); // nova caixinha em Tarefas, já focada
      });
    }
    // Avisa o estado inicial da hierarquia (grade = raiz) p/ o shell decidir
    // o voltar do sistema (troca de aba só na raiz).
    widget.onNaGradeMudou?.call(_modoPastas);
  }

  /// Troca grade ↔ pasta avisando o shell (ver [ProjetoScreen.onNaGradeMudou]).
  /// Centraliza as 3 transições (abrir pasta, voltar, alternar) p/ nenhuma
  /// esquecer o aviso.
  void _definirModoPastas(bool v) {
    if (_modoPastas == v) return;
    setState(() => _modoPastas = v);
    widget.onNaGradeMudou?.call(v);
  }

  /// Voltar da tela EMBUTIDA (botão da AppBar ou sistema já tratado pelo shell):
  /// dentro de pasta volta à grade; na grade, pede a troca de aba.
  void _voltarEmbutido() {
    if (!mounted) return;
    if (_modoPastas) {
      widget.onVoltarNaRaiz?.call();
    } else {
      _definirModoPastas(true);
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
    for (final c in _scrollAbas.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() => Storage.instance.salvar();

  GlobalKey<_CaixaNotaState> _chaveDa(String id) =>
      _chaves.putIfAbsent(id, () => GlobalKey<_CaixaNotaState>());

  List<Nota> _lista(int aba) => widget.projeto.notasDaAba(aba);

  void _adicionar(int aba, {String? comTexto}) {
    final nota = Nota(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      texto: comTexto ?? '',
    );
    setState(() {
      // Com busca ativa, a caixinha nova (vazia) seria filtrada pelo termo e
      // "sumiria" (o usuário achava que o + não funcionava, pois só aparecia
      // depois de fechar a lupa). Limpa a busca para ela aparecer e focar.
      if (_buscando || _ctrlBusca.text.isNotEmpty) {
        _buscando = false;
        _ctrlBusca.clear();
      }
      _lista(aba).add(nota);
    });
    // A caixinha nova entra no FIM. Com muitas caixinhas ela nasce fora da tela
    // e, como a lista é lazy, nem é construída → antes o foco/rolagem falhavam.
    // Rola a lista até o fim (construindo os itens no caminho) e então foca.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revelarNota(aba, nota.id));
    _salvar();
  }

  /// Rola a aba [aba] até a caixinha nova (última) e foca o campo dela. Repete o
  /// `animateTo` porque a lista é lazy: cada rolagem constrói mais itens e o
  /// `maxScrollExtent` cresce até o fim real.
  void _revelarNota(int aba, String id, {int tentativa = 0}) {
    final sc = _scrollDaAba(aba);
    if (!sc.hasClients) {
      if (tentativa < 8) {
        Future.delayed(const Duration(milliseconds: 120),
            () { if (mounted) _revelarNota(aba, id, tentativa: tentativa + 1); });
      }
      return;
    }
    final pos = sc.position;
    if (pos.pixels < pos.maxScrollExtent - 4 && tentativa < 8) {
      sc.animateTo(
        pos.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      ).then((_) {
        if (mounted) _revelarNota(aba, id, tentativa: tentativa + 1);
      });
      return;
    }
    // Chegou ao fim: a caixinha já está construída → foca (abre o teclado).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chaveDa(id).currentState?.focarNoFim();
    });
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
    final eraConcluida = nota.concluida;
    final emAndamentoAntes = widget.projeto.emAndamento;
    setState(() {
      lst.removeAt(i);
      if (eraConcluida) {
        final aindaTem = widget.projeto.tarefas.any((n) => n.concluida) ||
            widget.projeto.futuro.any((n) => n.concluida) ||
            widget.projeto.abasExtras.any((a) => a.notas.any((n) => n.concluida));
        if (!aindaTem) widget.projeto.emAndamento = false;
      }
    });
    _salvar();
    mostrarAvisoAcao(
      context,
      'Caixinha excluída',
      'Desfazer',
      () {
        setState(() {
          lst.insert(i > lst.length ? lst.length : i, nota);
          if (eraConcluida) widget.projeto.emAndamento = true;
          else widget.projeto.emAndamento = emAndamentoAntes;
        });
        _salvar();
      },
    );
  }

  void _moverOutraAba(int aba, int i) async {
    if (_qtdAbas <= 1) return;
    if (_qtdAbas == 2) {
      final nota = _lista(aba).removeAt(i);
      final destIdx = aba == 0 ? 1 : 0;
      final destino = _lista(destIdx);
      destino.add(nota);
      final nomeDestino = _nomeAba(destIdx);
      setState(() {});
      _salvar();
      mostrarAvisoAcao(context, 'Movida para $nomeDestino', 'Desfazer', () {
        setState(() {
          destino.remove(nota);
          final lst = _lista(aba);
          lst.insert(i > lst.length ? lst.length : i, nota);
        });
        _salvar();
      });
      return;
    }
    final escolha = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: EdgeInsets.all(16), child: Text('Mover para…', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          for (var j = 0; j < _qtdAbas; j++)
            if (j != aba)
              ListTile(
                leading: Icon(j == 0 ? Icons.checklist_rounded : j == 1 ? Icons.lightbulb_outline : Icons.folder_outlined),
                title: Text(_nomeAba(j)),
                onTap: () => Navigator.pop(ctx, j),
              ),
          SizedBox(height: 8),
        ]),
      ),
    );
    if (escolha == null) return;
    final nota = _lista(aba).removeAt(i);
    final destino = _lista(escolha);
    destino.add(nota);
    final nomeDestino = _nomeAba(escolha);
    setState(() {});
    _salvar();
    mostrarAvisoAcao(context, 'Movida para $nomeDestino', 'Desfazer', () {
      setState(() {
        destino.remove(nota);
        final lst = _lista(aba);
        lst.insert(i > lst.length ? lst.length : i, nota);
      });
      _salvar();
    });
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
    if (ok == true && mounted) {
      _saindo = true; // libera o pop no PopScope (senão voltaria à grade)
      Navigator.pop(context, 'excluir');
    }
  }

  void _copiarProjeto() {
    final p = widget.projeto;
    final buf = StringBuffer()
      ..writeln(p.nome)
      ..writeln('=' * 32);
    if (p.tarefas.isNotEmpty) {
      buf.writeln('  --- ${p.nomeTarefasEff} ---');
      for (final n in p.tarefas) {
        for (final linha in n.texto.split('\n')) {
          buf.writeln('  $linha');
        }
      }
    }
    if (p.futuro.isNotEmpty) {
      buf.writeln('  --- ${p.nomeFuturoEff} ---');
      for (final n in p.futuro) {
        for (final linha in n.texto.split('\n')) {
          buf.writeln('  $linha');
        }
      }
    }
    for (final a in p.abasExtras) {
      if (a.notas.isEmpty) continue;
      buf.writeln('  --- ${a.nome} ---');
      for (final n in a.notas) {
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
    final nomeAbaAtual = _nomeAba(aba);

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
                  hintText: 'Buscar em $nomeAbaAtual…',
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
                  scrollController: _scrollDaAba(aba),
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
                  itemBuilder: (_, i) {
                    final bottom = temaController.compacto ? 5.0 : 10.0;
                    // Arrastar a caixinha para a ESQUERDA exclui (com Desfazer
                    // via [_excluir]). Mesmo padrão dos cartões de projeto na
                    // home: Dismissible como widget de topo (carrega a key do
                    // item reordenável) + o reorder vem do pino interno
                    // (ReorderableDragStartListener), então os dois gestos
                    // coexistem.
                    return Dismissible(
                      key: ValueKey(filtradas[i].id),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) =>
                          _excluir(aba, _lista(aba).indexOf(filtradas[i])),
                      background: Container(
                        alignment: Alignment.centerRight,
                        margin: EdgeInsets.only(bottom: bottom),
                        padding: const EdgeInsets.only(right: 22),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.delete_outline,
                            color: Colors.redAccent),
                      ),
                      child: Padding(
                        padding: EdgeInsets.only(bottom: bottom),
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
                          // Marca/limpa esta caixinha como a "ativa" (alvo da
                          // barra única acima do teclado) conforme o foco.
                          onFoco: (temFoco) {
                            final id = filtradas[i].id;
                            if (temFoco) {
                              if (_idBlocoAtivo != id) {
                                setState(() => _idBlocoAtivo = id);
                              }
                            } else if (_idBlocoAtivo == id) {
                              setState(() => _idBlocoAtivo = null);
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _gradePastas() {
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.azul;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 100),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.25,
      ),
      itemCount: _qtdAbas,
      itemBuilder: (_, i) {
        final nome = _nomeAba(i);
        final qtd = _lista(i).length;
        final ehAtual = _tabCtrl.index == i;
        Widget card = Container(
          decoration: BoxDecoration(
            color: app.projetoCard,
            borderRadius: BorderRadius.circular(app.neumorfico ? 18 : 14),
            border: Border.all(
              color: ehAtual ? app.fab : app.projetoTxt.withValues(alpha: 0.08),
              width: ehAtual ? 1.6 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(app.neumorfico ? 18 : 14),
            onTap: () {
              _definirModoPastas(false);
              _tabCtrl.animateTo(i);
            },
            onLongPress: () => _renomearAba(i),
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(i == 0 ? Icons.checklist_rounded : i == 1 ? Icons.lightbulb_outline : Icons.folder_outlined, size: 22, color: app.fab),
                    Spacer(),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: app.fab.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                      child: Text('$qtd', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: app.fab)),
                    ),
                  ]),
                  Spacer(),
                  Text(nome, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: app.projetoTxt)),
                  SizedBox(height: 2),
                  Text(qtd == 1 ? '1 caixa' : '$qtd caixas', style: TextStyle(fontSize: 11.5, color: app.projetoTxt.withValues(alpha: 0.6))),
                ],
              ),
            ),
          ),
        );
        if (app.neumorfico) {
          card = Caixa3D(cor: app.projetoCard, corInicio: app.projetoCard, corFim: app.projetoCardFim, raio: 18, child: card);
        }
        return card;
      },
    );
  }

  /// FAB da tela (pasta nova / caixa nova). V0.1.222: um respiro à direita (8px)
  /// e mais folga do rodapé — o dono achava o '+' colado embaixo e à direita
  /// demais. Na aba Estudos (embutida no shell) sobe mais (94) p/ clarear a barra
  /// flutuante externa; em rota cheia, uma folga menor (12).
  Widget _botaoFlutuante() {
    final Widget fab = _modoPastas
        ? FloatingActionButton(
            heroTag: null,
            onPressed: _criarNovaAba,
            tooltip: 'Nova pasta',
            child: const Icon(Icons.create_new_folder_outlined),
          )
        : GestureDetector(
            onLongPress: _adicionarDeImagem,
            child: FloatingActionButton(
              heroTag: null,
              onPressed: () => _adicionar(_tabCtrl.index),
              tooltip: 'Nova caixa de texto',
              child: const Icon(Icons.add),
            ),
          );
    return Padding(
      padding: EdgeInsets.only(bottom: widget.embutido ? 94 : 12, right: 8),
      child: fab,
    );
  }

  // ===================================================================== //
  //  NOVO LAYOUT (V0.1.237): pílulas do topo + barra única de ferramentas   //
  // ===================================================================== //

  /// Pílula flutuante do topo: voltar (embutido), título do projeto, atalho da
  /// Muse e os botões pasta / PDF / copiar tudo / excluir.
  Widget _pilulaTopo(AppCores app) {
    final sec = app.textoUI.withValues(alpha: 0.66);
    const danger = Color(0xFFEF4444);
    return _Pilula(
      padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
      child: Row(
        children: [
          if (widget.embutido)
            _IconePilula(
              icone: Icons.chevron_left,
              cor: app.textoUI,
              tamanho: 24,
              tooltip: 'Voltar',
              onTap: _voltarEmbutido,
            ),
          SizedBox(width: widget.embutido ? 2 : 10),
          Expanded(
            child: Text(
              widget.projeto.nome,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: app.textoUI,
              ),
            ),
          ),
          // Atalho para o Muse (só com o recurso ligado): o ROSTO da Muse.
          if (ChatConfig.habilitado)
            Tooltip(
              message: 'Muse Spark (assistente)',
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    abrirAbaMuse?.call();
                  },
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(child: MuseBlob(size: 26)),
                  ),
                ),
              ),
            ),
          _IconePilula(
            icone: _modoPastas
                ? Icons.view_agenda_outlined
                : Icons.folder_outlined,
            cor: sec,
            tooltip: _modoPastas ? 'Ver como abas' : 'Ver como pastas',
            onTap: () => _definirModoPastas(!_modoPastas),
          ),
          _IconePilula(
            icone: Icons.picture_as_pdf_outlined,
            cor: app.fab,
            tooltip: 'Exportar PDF do projeto',
            onTap: () => exportarPdfProjeto(context, widget.projeto),
          ),
          _IconePilula(
            icone: Icons.copy_all_outlined,
            cor: sec,
            tooltip: 'Copiar tudo do projeto',
            onTap: _copiarProjeto,
          ),
          if (!widget.embutido)
            _IconePilula(
              icone: Icons.delete_outline,
              cor: danger,
              tooltip: 'Excluir projeto',
              onTap: _excluirProjeto,
            ),
        ],
      ),
    );
  }

  /// Linha de abas (Tarefas/Ideias/…) numa pílula + botões redondos de nova
  /// aba e busca. A seleção continua pelo [TabBar] real (indicador em cápsula).
  Widget _pilulaAbas(AppCores app) {
    final sec = app.textoUI.withValues(alpha: 0.6);
    final rolavel = _qtdAbas > 2;
    return Row(
      children: [
        Expanded(
          child: _Pilula(
            padding: const EdgeInsets.all(4),
            child: TabBar(
              controller: _tabCtrl,
              isScrollable: rolavel,
              tabAlignment: rolavel ? TabAlignment.start : TabAlignment.fill,
              indicator: BoxDecoration(
                color: app.fab,
                borderRadius: BorderRadius.circular(999),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: EdgeInsets.zero,
              dividerColor: Colors.transparent,
              labelColor: app.fabIcone,
              unselectedLabelColor: sec,
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              unselectedLabelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
              overlayColor:
                  WidgetStateProperty.all<Color>(Colors.transparent),
              tabs: [
                for (var i = 0; i < _qtdAbas; i++)
                  GestureDetector(
                    onLongPress: () => _renomearAba(i),
                    child: Tab(height: 34, text: _nomeAba(i)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _Pilula(
          child: _IconePilula(
            icone: Icons.add,
            cor: sec,
            caixa: 42,
            tamanho: 20,
            tooltip: 'Nova aba / ver abas',
            onTap: _mostrarSheetAbas,
          ),
        ),
        const SizedBox(width: 6),
        _Pilula(
          child: _IconePilula(
            icone: _buscando ? Icons.close : Icons.search,
            cor: sec,
            caixa: 42,
            tamanho: 19,
            tooltip: _buscando ? 'Fechar busca' : 'Buscar na aba',
            onTap: _alternarBusca,
          ),
        ),
      ],
    );
  }

  /// Barra única de ferramentas, acima do teclado, operando sobre a caixinha
  /// [ativo] (a última focada). Copiar e a caixa de seleção ficam no dock do
  /// card; aqui vão TODAS as demais ferramentas, na ordem configurada.
  Widget _barraInferior(AppCores app, _CaixaNotaState ativo) {
    final corBarra = app.barraFerramentas;
    final onBarra =
        ThemeData.estimateBrightnessForColor(corBarra) == Brightness.dark
            ? Colors.white
            : Colors.black87;
    return Material(
      color: corBarra,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Indicador discreto do bloco em edição.
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: app.notaBorda)),
            ),
            padding: const EdgeInsets.fromLTRB(14, 5, 14, 5),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: app.fab, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('Editando: ',
                    style: TextStyle(
                        fontSize: 11,
                        color: onBarra.withValues(alpha: 0.55))),
                Expanded(
                  child: Text(
                    ativo.resumoLinha,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: onBarra),
                  ),
                ),
              ],
            ),
          ),
          // Ferramentas roláveis horizontalmente (ordem do barraController).
          SizedBox(
            height: 50,
            child: ListenableBuilder(
              listenable: barraController,
              builder: (context, _) {
                final botoes = <Widget>[];
                for (final f in barraController.ordem) {
                  // Copiar e "feito" moram no dock do card.
                  if (f == Ferramenta.copiar || f == Ferramenta.feito) {
                    continue;
                  }
                  final b = ativo.construirBotaoBarra(
                      f, onBarra, () => setState(() {}));
                  if (b != null) botoes.add(b);
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(children: botoes),
                );
              },
            ),
          ),
        ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Cor do desenho = acento do tema ativo (cada tema pinta com a sua cor).
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.azul;
    return Fundo(
      // Projeto aberto "em modo pastas" (ex.: Estudos): o 1º voltar, estando
      // dentro de uma pasta, retorna À GRADE de pastas — só o 2º voltar sai
      // para a lista de projetos.
      child: PopScope(
        // Embutido no shell: nunca pop (não há rota). Dentro de uma pasta, o
        // voltar volta à grade; na grade, avisa o shell (troca de aba).
        canPop: widget.embutido
            ? false
            : (_modoPastas || !widget.modoPastasInicial || _saindo),
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || !mounted) return;
          if (widget.embutido && _modoPastas) {
            widget.onVoltarNaRaiz?.call();
          } else {
            _definirModoPastas(true);
          }
        },
        child: Scaffold(
        // NOVO LAYOUT (V0.1.237): barra do topo e abas viram PÍLULAS
        // flutuantes sobre o fundo. A AppBar fica transparente e só segura o
        // recorte da status bar; o conteúdo vem das pílulas.
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          toolbarHeight: 62,
          systemOverlayStyle: Theme.of(context).brightness == Brightness.light
              ? SystemUiOverlayStyle.dark
              : SystemUiOverlayStyle.light,
          title: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
            child: _pilulaTopo(app),
          ),
          bottom: _modoPastas
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(60),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
                    child: _pilulaAbas(app),
                  ),
                ),
        ),
      // heroTag: null — sem Hero: a tela pode estar EMBUTIDA no shell (aba
      // Estudos) ao mesmo tempo que um outro ProjetoScreen é empilhado; dois FABs
      // com a tag padrão colidiriam/animariam entre rotas. O FAB não precisa de
      // voo de Hero aqui.
      // Embutido: sobe o FAB p/ não ficar ATRÁS da barra flutuante externa
      // (78 = 64 da barra + 4 + 10 dos respiros); em rota cheia, sem padding.
      // BARRA ÚNICA de ferramentas (V0.1.237): única, operando sobre a caixinha
      // em EDIÇÃO (a focada). Como `bottomNavigationBar`, o Scaffold a posiciona
      // automaticamente ACIMA do teclado (resizeToAvoidBottomInset). Só aparece
      // enquanto há uma caixinha focada; some ao fechar o teclado (perde o foco).
      bottomNavigationBar: (_modoPastas || _blocoAtivo == null)
          ? null
          : _barraInferior(app, _blocoAtivo!),
      floatingActionButton: _botaoFlutuante(),
      body: _modoPastas
          ? _gradePastas()
          : TabBarView(
              controller: _tabCtrl,
              children: [
                for (var i = 0; i < _qtdAbas; i++) _listaCard(i),
              ],
            ),
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
    this.onFoco,
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

  /// Avisado quando esta caixinha ganha (`true`) ou perde (`false`) o foco. A
  /// tela marca a que está focada como o bloco "ativo" (alvo da barra única de
  /// ferramentas acima do teclado) e esconde a barra quando nenhuma edita.
  final ValueChanged<bool>? onFoco;

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
  double _insetBottomAnterior = 0;
  Timer? _reabrirTimer;
  int _tentativaReabrir = 0;
  bool _retomando = false;
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
  /// então não dava para continuar digitando. Guardamos que a caixinha estava
  /// sendo editada ao sair (`_tinhaFocoAoParar`) e, ao voltar, recriamos a
  /// conexão. V0.1.83: escada 220/520/900 com verificação `viewInsets` e janela
  /// `_retomando` que suprime o `didChangeMetrics` durante a transição (fix do
  /// "subiu e baixou" no desbloqueio facial).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_foco.hasFocus) _tinhaFocoAoParar = true;
      _cancelarReabertura();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    if (!_tinhaFocoAoParar) return;
    _tinhaFocoAoParar = false;
    _retomando = true;
    _tentativaReabrir = 0;
    _agendarTentativaReabrir();
  }

  void _cancelarReabertura() {
    _reabrirTimer?.cancel();
    _reabrirTimer = null;
    _retomando = false;
    _tentativaReabrir = 0;
  }

  void _agendarTentativaReabrir() {
    const atrasosAbs = [220, 520, 900];
    if (_tentativaReabrir >= atrasosAbs.length) {
      _retomando = false;
      return;
    }
    final ms = _tentativaReabrir == 0
        ? atrasosAbs[0]
        : atrasosAbs[_tentativaReabrir] - atrasosAbs[_tentativaReabrir - 1];
    _reabrirTimer?.cancel();
    _reabrirTimer = Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        _retomando = false;
        return;
      }
      final bottom = View.of(context).viewInsets.bottom;
      if (bottom > 0) {
        _tentativaReabrir++;
        if (_tentativaReabrir < atrasosAbs.length) {
          _agendarTentativaReabrir();
        } else {
          _retomando = false;
        }
        return;
      }
      if (!_foco.hasFocus) _foco.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
      _tentativaReabrir++;
      if (_tentativaReabrir < atrasosAbs.length) {
        _agendarTentativaReabrir();
      } else {
        _retomando = false;
      }
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
    if (_retomando) return;
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
    _reabrirTimer?.cancel();
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
    // Avisa a tela: focada = alvo da barra única; desfocada = esconde a barra.
    widget.onFoco?.call(_foco.hasFocus);
    if (_foco.hasFocus) {
      if (mounted) _insetBottomAnterior = View.of(context).viewInsets.bottom;
      return;
    }
    _guardarTudo();
  }

  /// Expande a caixinha se estiver minimizada.
  void _garantirExpandida() {
    if (!widget.nota.minimizada) return;
    setState(() => widget.nota.minimizada = false);
    Storage.instance.salvar();
  }

  /// Alterna o estado minimizado (botão "•••"): minimizada OCULTA a barra de
  /// ferramentas e mostra só as 3 primeiras linhas do texto, com os botões
  /// copiar e "•••" no fim da 3ª linha (o "•••" expande de volta). Fica salvo
  /// no modelo, então é lembrado ao fechar e reabrir o projeto/app.
  void _alternarMinimizada() {
    // Derrama o texto (inclusive composição da IME) antes de esconder o campo.
    _guardarTudo();
    _debounce?.cancel();
    _foco.unfocus();
    setState(() => widget.nota.minimizada = !widget.nota.minimizada);
    Storage.instance.salvar();
  }

  /// Largura reservada para o botão "•••" (expandir) da prévia minimizada.
  /// (Copiar/arrastar/seleção ficam no dock à direita do card, sempre visível.)
  static const double _larguraBotoesPrevia = 36;

  /// Prévia da caixinha minimizada: as 3 primeiras linhas do texto e, no fim da
  /// 3ª linha, o botão "•••" (expandir). Tocar na prévia também expande. O
  /// texto é medido e cortado numa fronteira de palavra para o botão caber SEM
  /// reticências: o próprio "•••" sinaliza que há mais conteúdo.
  Widget _previaMinimizada(BuildContext context, Color corTexto) {
    final estilo = (_estiloCampo ?? _estiloTexto).copyWith(color: corTexto);
    return LayoutBuilder(
      builder: (context, constraints) {
        final larguraTexto = constraints.maxWidth - _larguraBotoesPrevia;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: _textoPrevia(context, estilo, larguraTexto),
                  style: estilo,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            _BotaoPrevia(
              icone: Icons.more_horiz,
              tooltip: 'Expandir caixinha',
              onTap: _alternarMinimizada,
              cor: corTexto,
            ),
          ],
        );
      },
    );
  }

  /// Texto visível na prévia minimizada: no máximo 3 linhas, cortado numa
  /// fronteira de palavra para os botões caberem no fim da 3ª linha.
  String _textoPrevia(BuildContext context, TextStyle estilo, double largura) {
    final texto = _ctrl.text;
    if (texto.isEmpty || largura <= 0) return texto;
    final painter = TextPainter(
      text: TextSpan(text: texto, style: estilo),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 3,
    )..layout(maxWidth: largura);
    if (!painter.didExceedMaxLines) return texto;
    final fim = painter.getPositionForOffset(
      Offset(largura, painter.height - painter.preferredLineHeight / 2),
    );
    if (fim.offset >= texto.length) return texto;
    var visivel = texto.substring(0, fim.offset);
    // Corte no MEIO de uma palavra (linha quebrada por largura): recua até a
    // fronteira anterior. Corte numa quebra "dura" (\n) já é limpo.
    if (texto[fim.offset].trim().isNotEmpty) {
      final fronteira = visivel.lastIndexOf(RegExp(r'\s'));
      if (fronteira > 0) visivel = visivel.substring(0, fronteira);
    }
    return visivel.trimRight();
  }

  void focarNoFim() {
    _garantirExpandida();
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
    _garantirExpandida();
    _ctrl.clear();
    _mudou('');
  }

  /// Restaura o último texto apagado/alterado — cobre também as ações da
  /// barra (centralizar, numerar, item de to-do).
  void _desfazer() {
    final restaurado = _historico.desfazer();
    if (restaurado == null) return;
    _garantirExpandida();
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
    _garantirExpandida();
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
    _garantirExpandida();
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
    _garantirExpandida();
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
    _garantirExpandida();
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

  /// Primeira linha com conteúdo da caixinha (rótulo do bloco ativo na barra
  /// única). Vazio → "Caixa de texto".
  String get resumoLinha {
    for (final linha in _ctrl.text.split('\n')) {
      final t = linha.trim();
      if (t.isNotEmpty) return t;
    }
    return 'Caixa de texto';
  }

  /// Constrói o botão da ferramenta [f] para a BARRA ÚNICA (acima do teclado),
  /// ou null quando ela não se aplica (ex.: "numerar" só na aba Tarefas).
  /// [aoAgir] roda após a ação para a barra se reconstruir (ícones que
  /// alternam: numerar, minimizar, comentário…). Copiar e "feito" moram no
  /// dock do card e não passam por aqui.
  Widget? construirBotaoBarra(Ferramenta f, Color onBarra, VoidCallback aoAgir) {
    _BotaoMini mini(IconData icone, String tooltip, VoidCallback onTap,
            {bool isDanger = false}) =>
        _BotaoMini(
          icone: icone,
          tooltip: tooltip,
          isDanger: isDanger,
          cor: onBarra,
          onTap: () {
            onTap();
            aoAgir();
          },
        );
    switch (f) {
      case Ferramenta.copiar:
        return mini(Icons.copy_all_outlined, 'Copiar', widget.onCopiar);
      case Ferramenta.desfazer:
        return mini(Icons.undo, 'Desfazer apagar', _desfazer);
      case Ferramenta.feito:
        return mini(
          widget.nota.concluida
              ? Icons.check_box
              : Icons.check_box_outline_blank,
          widget.nota.concluida ? 'Desmarcar' : 'Marcar como feito',
          _alternarConcluida,
        );
      case Ferramenta.numerar:
        if (!widget.modoTarefas) return null;
        return mini(
          _numerado ? Icons.format_list_numbered : Icons.format_align_justify,
          _numerado ? 'Remover número da linha' : 'Numerar linha',
          _alternarNumero,
        );
      case Ferramenta.todo:
        return mini(Icons.checklist, 'Item de to-do (☐)', _inserirTodo);
      case Ferramenta.mover:
        return mini(
          widget.modoTarefas ? Icons.arrow_downward : Icons.arrow_upward,
          widget.modoTarefas ? 'Mover para Ideias' : 'Mover para Tarefas',
          widget.onMover,
        );
      case Ferramenta.extremo:
        return mini(Icons.unfold_more, 'Topo / Pé', _irAoExtremo);
      case Ferramenta.link:
        return mini(Icons.add_link, 'Link', _abrirLink);
      case Ferramenta.imagem:
        return mini(
            Icons.image_outlined, 'Ler texto de imagem (OCR)', _lerImagem);
      case Ferramenta.comentario:
        return mini(
          _comentarioExpandido ? Icons.chat_bubble : Icons.chat_bubble_outline,
          'Comentário',
          () => setState(() => _comentarioExpandido = !_comentarioExpandido),
        );
      case Ferramenta.editar:
        return mini(Icons.edit_outlined, 'Editar', focarNoFim);
      case Ferramenta.centralizar:
        return mini(Icons.format_align_center, 'Centralizar linha (seleção)',
            _centralizarLinha);
      case Ferramenta.minimizar:
        return mini(
          Icons.more_horiz,
          widget.nota.minimizada ? 'Expandir caixinha' : 'Minimizar caixinha',
          _alternarMinimizada,
        );
      case Ferramenta.limpar:
        return mini(Icons.cleaning_services, 'Limpar conteúdo', _limpar);
      case Ferramenta.excluir:
        return mini(Icons.delete_outline, 'Excluir', widget.onExcluir,
            isDanger: true);
    }
  }

  /// Dock vertical à direita do card (V0.1.237): arrastar (reordenar), copiar e
  /// a caixa de seleção que marca o bloco como "em andamento". As demais
  /// ferramentas ficam na barra única acima do teclado.
  Widget _dock(AppCores app) {
    final sec = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: app.notaBorda)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Arrastar para reordenar',
            child: ReorderableDragStartListener(
              index: widget.indice,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.drag_indicator,
                    size: 20, color: sec.withValues(alpha: 0.85)),
              ),
            ),
          ),
          _BotaoMini(
            icone: Icons.copy_all_outlined,
            tooltip: 'Copiar',
            onTap: widget.onCopiar,
            cor: sec,
          ),
          _BotaoMini(
            icone: widget.nota.concluida
                ? Icons.check_box
                : Icons.check_box_outline_blank,
            tooltip: widget.nota.concluida
                ? 'Desmarcar (em andamento)'
                : 'Marcar como em andamento',
            onTap: _alternarConcluida,
            cor: widget.nota.concluida ? app.fab : sec,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.azul;

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

    // Minimizada (botão "•••") mostra só as 3 primeiras linhas com reticências.
    // Com busca ativa a caixinha aparece EXPANDIDA (sem mudar o estado salvo):
    // a ocorrência pode estar além da 3ª linha e ficaria escondida.
    final mostrarMinimizada =
        widget.nota.minimizada && widget.termoBusca.trim().isEmpty;

    // Minimizada esconde o campo de comentário (os TÍTULOS dos links seguem
    // visíveis na subcaixinha abaixo).
    _comentarioVisivel = !mostrarMinimizada &&
        (_comentarioExpandido ||
            (!widget.modoTarefas &&
                (widget.nota.comentario?.isNotEmpty ?? false)));

    final corTexto = widget.nota.concluida
        ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)
        : Theme.of(context).colorScheme.onSurface;

    return Caixa3D(
      cor: app.notaInicio,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // NOVO LAYOUT (V0.1.237): o texto ocupa a esquerda e o DOCK vertical
          // (arrastar, copiar, caixa de seleção) fica à direita. A barra de
          // ferramentas antiga (topo do card) virou a barra ÚNICA acima do
          // teclado — ver _ProjetoScreenState._barraInferior.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: mostrarMinimizada
                    // Prévia minimizada: as 3 primeiras linhas do texto; tocar
                    // (ou o "•••") expande de volta. Com busca ativa aparece
                    // expandida (o grifo fica correto lá).
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _alternarMinimizada,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
                          child: _previaMinimizada(context, corTexto),
                        ),
                      )
                    : Listener(
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
                    color: corTexto,
                  ),
                  contextMenuBuilder: _menuSelecao,
                  onChanged: _mudou,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    // Sem fill: o fundo é o da Caixa3D (cor única, sem bloco
                    // interno mais escuro do tema).
                    filled: false,
                    contentPadding: EdgeInsets.fromLTRB(14, 2, 14, 14),
                  ),
                ),
              ),
            ),
              ),
              _dock(app),
            ],
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
                        // Sem fill: o fundo é o da subcaixinha (cor única).
                        filled: false,
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
    // Botão segue o gradiente da barra quando ela tem cor própria;
    // senão usa a superfície padrão do tema.
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

/// Botão compacto do fim da 3ª linha da prévia minimizada (copiar / "•••").
/// Menor que o `_BotaoMini` da barra para caber no fim de uma linha de texto.
class _BotaoPrevia extends StatelessWidget {
  const _BotaoPrevia({
    required this.icone,
    required this.tooltip,
    required this.onTap,
    required this.cor,
  });

  final IconData icone;
  final String tooltip;
  final VoidCallback onTap;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.azul;
    if (app.neumorfico) {
      return BotaoNeum(
        raio: 9,
        padding: const EdgeInsets.all(5),
        tooltip: tooltip,
        onTap: onTap,
        child: Icon(icone, size: 17, color: cor),
      );
    }
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icone, size: 18, color: cor),
        ),
      ),
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

  Future<void> _copiar() async {
    final links = _ctrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    if (links.isEmpty) {
      mostrarAviso(context, 'Nenhum link para copiar.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: links.join('\n')));
    if (!mounted) return;
    mostrarAviso(context, links.length == 1 ? 'Link copiado!' : '${links.length} links copiados!');
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
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Copiar',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: _copiar,
              icon: const Icon(Icons.content_copy_rounded, size: 18),
            ),
            IconButton(
              tooltip: 'Colar',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: _colar,
              icon: const Icon(Icons.content_paste_rounded, size: 18),
            ),
            IconButton(
              tooltip: 'Limpar',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: _limpar,
              icon: const Icon(Icons.cleaning_services_rounded, size: 18),
            ),
            IconButton(
              tooltip: 'Fechar',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
            const SizedBox(width: 4),
            FilledButton(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(8),
                minimumSize: const Size(36, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
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
              child: const Icon(Icons.check_rounded, size: 18),
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

/// Qual desenho vai na plaquinha do topo do projeto (ideia 04 da galeria).
/// Botão GHOST do topo do projeto: ÍCONE Material padrão, sem caixa — usado em
/// Pastas/PDF/Copiar/Excluir/Voltar com `cor` = texto da UI. (V0.1.222: os
/// glifos desenhados à mão — `_TopoPainter` — pareciam fora do padrão; trocados
/// por ícones Material.) Vale em todos os temas (a cor vem do tema).
/// Superfície "pílula" flutuante do novo layout (V0.1.237): barra do topo,
/// linha de abas e botões redondos. Usa as cores do tema (branca nos claros,
/// navy/preta nos escuros), borda sutil e uma sombra leve.
class _Pilula extends StatelessWidget {
  const _Pilula({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.azul;
    final escuro = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: app.notaInicio,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: app.notaBorda),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: escuro ? 0.22 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Botão-ícone fino (sem caixa) usado dentro das pílulas do topo/abas.
class _IconePilula extends StatelessWidget {
  const _IconePilula({
    required this.icone,
    required this.cor,
    required this.tooltip,
    required this.onTap,
    this.tamanho = 18,
    this.caixa = 36,
  });
  final IconData icone;
  final Color cor;
  final String tooltip;
  final VoidCallback onTap;
  final double tamanho;
  final double caixa;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: SizedBox(
            width: caixa,
            height: caixa,
            child: Center(child: Icon(icone, size: tamanho, color: cor)),
          ),
        ),
      ),
    );
  }
}

