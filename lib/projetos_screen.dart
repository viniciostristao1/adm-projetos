import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'barra_config.dart';
import 'caixa3d.dart';
import 'cores.dart';
import 'editor.dart';
import 'models.dart';
import 'projeto_screen.dart';
import 'storage.dart';
import 'sync_service.dart';
import 'tema.dart';
import 'versao.dart';

/// Página principal: a lista de projetos.
class ProjetosScreen extends StatefulWidget {
  const ProjetosScreen({super.key});

  @override
  State<ProjetosScreen> createState() => _ProjetosScreenState();
}

class _ProjetosScreenState extends State<ProjetosScreen> {
  List<Projeto> _projetos = [];
  List<Projeto> _recentes = [];
  final TextEditingController _ctrlBusca = TextEditingController();
  final FocusNode _focoBusca = FocusNode();
  bool _buscando = false;

  @override
  void initState() {
    super.initState();
    Storage.instance.carregar().then((p) {
      if (mounted) setState(() => _projetos = p);
      _recarregarRecentes();
      if (Storage.instance.recuperadoDeCorrupcao && mounted) {
        mostrarAviso(
          context,
          'Arquivo de dados danificado foi REPARADO: '
          '${p.length} projetos recuperados.',
        );
      }
    });
    // Quando a nuvem baixa dados, recarrega a lista.
    Storage.instance.addListener(_aoMudarStorage);
  }

  @override
  void dispose() {
    Storage.instance.removeListener(_aoMudarStorage);
    _ctrlBusca.dispose();
    _focoBusca.dispose();
    super.dispose();
  }

  /// Reconstroi a prateleira "Últimos abertos" a partir dos IDs salvos
  /// (apenas projetos que ainda existem, na ordem: mais recente primeiro).
  Future<void> _recarregarRecentes() async {
    final ids = await Storage.instance.recentesIds();
    if (!mounted) return;
    setState(() {
      _recentes = ids
          .map((id) => _projetos.where((p) => p.id == id).firstOrNull)
          .whereType<Projeto>()
          .toList();
    });
  }

  Future<void> _aoMudarStorage() async {
    // IMPORTANTE: sem List.of — a tela precisa apontar para a MESMA lista
    // interna do Storage; copiar desliga as edições do salvamento (bug de
    // "dados que somem").
    final p = await Storage.instance.carregar();
    if (mounted) setState(() => _projetos = p);
    _recarregarRecentes();
  }

  Future<void> _salvar() => Storage.instance.salvar();

  /// Reordena a lista de projetos após arrastar (troca a ordem das pastas).
  void _reordenar(int antigo, int novo) {
    setState(() {
      final p = _projetos.removeAt(antigo);
      _projetos.insert(novo, p);
    });
    _salvar();
  }

  /// Reordena quando a lista está em SEÇÕES (EM ANDAMENTO / OUTROS): só
  /// permite mover DENTRO da seção do projeto arrastado — não deixa
  /// atravessar o cabeçalho.
  void _reordenarComSecoes(int oldIndex, int newIndex) {
    final ativos = _projetos.where((p) => p.emAndamento).toList();
    final outros = _projetos.where((p) => !p.emAndamento).toList();
    final linhas = <Object>[
      'EM ANDAMENTO · ${ativos.length}',
      ...ativos,
      if (outros.isNotEmpty) 'OUTROS · ${outros.length}',
      ...outros,
    ];
    final alvo = linhas[oldIndex];
    if (alvo is! Projeto) return;
    if (newIndex > oldIndex) newIndex--;
    if (newIndex == oldIndex) return;
    // Limites visuais da seção (só posições de projeto).
    var ini = oldIndex;
    while (ini > 0 && linhas[ini - 1] is Projeto) {
      ini--;
    }
    var fim = oldIndex;
    while (fim < linhas.length - 1 && linhas[fim + 1] is Projeto) {
      fim++;
    }
    if (newIndex < ini || newIndex > fim) return;
    final grupo = alvo.emAndamento ? ativos : outros;
    final grupoSem = grupo.where((p) => p.id != alvo.id).toList();
    final dest = (newIndex - ini).clamp(0, grupoSem.length);
    final novoGrupo = [...grupoSem]..insert(dest, alvo);
    setState(() {
      var gi = 0;
      _projetos = [
        for (final p in _projetos)
          if (grupo.any((g) => g.id == p.id)) novoGrupo[gi++] else p,
      ];
    });
    _salvar();
  }

  void _copiarTudo() {
    final buf = StringBuffer()
      ..writeln('ADM-projetos  —  Backup')
      ..writeln('=' * 36);

    for (final p in _projetos) {
      buf.writeln();
      buf.writeln('- - -');
      buf.writeln(p.nome);
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
    }
    final texto = buf.toString();
    Clipboard.setData(ClipboardData(text: texto));
    mostrarAviso(context, 'Backup copiado (todos os projetos)!');
  }

  Future<void> _abrirConfig() async {
    await showModalBottomSheet<String>(
      context: context,
      // showDragHandle: a alça no topo vira um alvo de arraste CONFIÁVEL para
      // fechar a folha puxando para baixo — antes, o SingleChildScrollView do
      // conteúdo engolia o gesto e só dava para sair pelo botão "voltar" do
      // Android. enableDrag já é true por padrão.
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ConfigSheet(),
    );
    if (!mounted) return;
    // Sem List.of: a tela deve usar a MESMA lista interna do Storage
    // (copiar desliga as edições do salvamento).
    final p = await Storage.instance.carregar();
    if (mounted) setState(() => _projetos = p);
  }

  Future<void> _criarProjeto() async {
    final nome = await _pedirNome(context, titulo: 'Novo projeto');
    if (nome == null || nome.trim().isEmpty) return;
    setState(() {
      _projetos.add(Projeto(id: DateTime.now().millisecondsSinceEpoch.toString(),
          nome: nome.trim()));
    });
    await _salvar();
  }

  Future<void> _renomear(Projeto p) async {
    final nome = await _pedirNome(context, titulo: 'Renomear projeto',
        inicial: p.nome);
    if (nome == null || nome.trim().isEmpty) return;
    setState(() => p.nome = nome.trim());
    await _salvar();
  }

  /// Alterna o "em andamento" do projeto (✓ verde no cartão da lista).
  void _alternarAndamento(Projeto p) {
    setState(() => p.emAndamento = !p.emAndamento);
    _salvar();
  }

  Future<void> _excluir(Projeto p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir projeto?'),
        content: Text('"${p.nome}" e todas as suas caixas serão apagados.'),
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
    if (ok == true) {
      final idx = _projetos.indexOf(p);
      setState(() => _projetos.remove(p));
      // Exclusão EXPLÍCITA do último projeto: autoriza a gravação da lista
      // vazia (a guarda anti-esvaziamento do Storage bloqueia o resto).
      if (_projetos.isEmpty) Storage.instance.liberarEsvaziamento();
      await _salvar();
      Storage.instance.removerRecente(p.id);
      _recarregarRecentes();
      if (!mounted) return;
      mostrarAvisoAcao(
        context,
        'Projeto excluído',
        'Desfazer',
        () {
          setState(() => _projetos.insert(
              idx > _projetos.length ? _projetos.length : idx, p));
          Storage.instance.registrarAbertura(p.id);
          _recarregarRecentes();
          _salvar();
        },
      );
    }
  }

  /// Abre o projeto (também registra na prateleira "Últimos abertos").
  Future<void> _abrirProjeto(Projeto p) async {
    await Storage.instance.registrarAbertura(p.id);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProjetoScreen(projeto: p)),
    );
    await _salvar();
    if (mounted) setState(() {});
    _recarregarRecentes();
  }

  /// Abre/fecha a lupa (busca global: projetos + conteúdo das caixinhas).
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

  /// Abre o projeto direto na caixinha encontrada pela busca global (aba
  /// certa + termo destacado + rolagem até a caixinha).
  Future<void> _abrirNota(_ResultadoBusca r) async {
    await Storage.instance.registrarAbertura(r.projeto.id);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjetoScreen(
          projeto: r.projeto,
          abaInicial: r.aba,
          termoInicial: _ctrlBusca.text.trim(),
          notaAlvo: r.nota.id,
        ),
      ),
    );
    await _salvar();
    if (mounted) setState(() {});
    _recarregarRecentes();
  }

  /// Monta a lista de resultados da lupa: projetos por NOME + caixinhas cujo
  /// texto/comentário contêm o termo, nas duas abas de todos os projetos.
  Widget _resultadosBusca(String q) {
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.azul;
    final projetosNome =
        _projetos.where((p) => p.nome.toLowerCase().contains(q)).toList();
    final conteudo = <_ResultadoBusca>[];
    for (final p in _projetos) {
      void varrer(List<Nota> lista, int aba) {
        for (final n in lista) {
          final alvo = '${n.texto}\n${n.comentario ?? ''}'.toLowerCase();
          if (alvo.contains(q)) {
            conteudo.add(_ResultadoBusca(
              projeto: p,
              aba: aba,
              nota: n,
              trecho: _trecho(n.texto, n.comentario, q),
            ));
          }
        }
      }

      varrer(p.tarefas, 0);
      varrer(p.futuro, 1);
    }
    if (projetosNome.isEmpty && conteudo.isEmpty) {
      return const Center(
          child: Text('Nada encontrado.',
              style: TextStyle(color: Colors.grey)));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 150),
      children: [
        if (projetosNome.isNotEmpty) ...[
          _cabecalhoResultado('PROJETOS', app),
          for (final p in projetosNome) _cartaoProjetoResultado(p, q, app),
        ],
        if (conteudo.isNotEmpty) ...[
          _cabecalhoResultado('NAS CAIXINHAS', app),
          for (final r in conteudo) _cartaoConteudoResultado(r, q, app),
        ],
      ],
    );
  }

  /// Primeira linha (ou trecho) que contém o termo, recortada em ~90 chars
  /// centrados na ocorrência, para o resultado da busca.
  String _trecho(String texto, String? comentario, String q) {
    String? achar(String fonte) {
      for (final linha in fonte.split('\n')) {
        if (linha.toLowerCase().contains(q)) return linha.trim();
      }
      return null;
    }

    final t = achar(texto) ??
        (comentario != null ? achar(comentario) : null);
    final base = (t == null || t.isEmpty)
        ? texto.trim().replaceAll('\n', ' ')
        : t;
    const max = 90;
    if (base.length <= max) return base;
    final pos = base.toLowerCase().indexOf(q);
    if (pos < 0) return '${base.substring(0, max)}…';
    var start = pos - 30;
    if (start < 0) start = 0;
    var end = start + max;
    if (end > base.length) {
      end = base.length;
      start = (end - max).clamp(0, base.length);
    }
    final prefixo = start > 0 ? '…' : '';
    final sufixo = end < base.length ? '…' : '';
    return '$prefixo${base.substring(start, end)}$sufixo';
  }

  /// Texto com as ocorrências do termo destacadas (fundo amarelo + negrito).
  Widget _textoDestacado(String texto, String q, TextStyle base,
      {int maxLines = 2}) {
    final lower = texto.toLowerCase();
    if (q.isEmpty || !lower.contains(q)) {
      return Text(texto,
          style: base, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }
    final spans = <TextSpan>[];
    var from = 0;
    while (true) {
      final idx = lower.indexOf(q, from);
      if (idx < 0) {
        spans.add(TextSpan(text: texto.substring(from)));
        break;
      }
      if (idx > from) spans.add(TextSpan(text: texto.substring(from, idx)));
      spans.add(TextSpan(
        text: texto.substring(idx, idx + q.length),
        style: const TextStyle(
          backgroundColor: Color(0x59FFC107),
          fontWeight: FontWeight.w800,
        ),
      ));
      from = idx + q.length;
    }
    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _cabecalhoResultado(String texto, AppCores app) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
        child: Text(
          texto,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: app.textoUI.withValues(alpha: 0.55),
          ),
        ),
      );

  Widget _cartaoResultado(
      {required AppCores app,
      required VoidCallback onTap,
      required Widget child}) {
    final ehClaude = app == AppCores.claude;
    final raio = ehClaude ? 10.0 : 14.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(raio),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: app.projetoCard,
              borderRadius: BorderRadius.circular(raio),
              border: Border.all(
                color: ehClaude
                    ? const Color(0xFF2A2A2B)
                    : app.projetoTxt.withValues(alpha: 0.08),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _cartaoProjetoResultado(Projeto p, String q, AppCores app) =>
      _cartaoResultado(
        app: app,
        onTap: () => _abrirProjeto(p),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(Icons.folder_outlined,
                  size: 20, color: app.projetoTxt.withValues(alpha: 0.7)),
              const SizedBox(width: 12),
              Expanded(
                child: _textoDestacado(
                  p.nome,
                  q,
                  TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: app.projetoTxt,
                  ),
                  maxLines: 1,
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20, color: app.projetoTxt.withValues(alpha: 0.4)),
            ],
          ),
        ),
      );

  Widget _cartaoConteudoResultado(_ResultadoBusca r, String q, AppCores app) {
    final abaTxt = r.aba == 0 ? 'Tarefas' : 'Ideias';
    return _cartaoResultado(
      app: app,
      onTap: () => _abrirNota(r),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  r.aba == 0
                      ? Icons.check_circle_outline
                      : Icons.lightbulb_outline,
                  size: 14,
                  color: app.fab,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${r.projeto.nome} · $abaTxt',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: app.projetoTxt.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 18, color: app.projetoTxt.withValues(alpha: 0.4)),
              ],
            ),
            const SizedBox(height: 5),
            _textoDestacado(
              r.trecho,
              q,
              TextStyle(fontSize: 13.5, color: app.projetoTxt),
              maxLines: 2,
            ),
          ],
        ),
      ),
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
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              child: Image.asset(
                'assets/icono.png',
                width: 24,
                height: 24,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Taskix',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              appVersao,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(_buscando ? Icons.close : Icons.search),
            tooltip: _buscando ? 'Fechar busca' : 'Buscar projeto',
            onPressed: _alternarBusca,
          ),
          IconButton(
            icon: const Icon(Icons.copy_all_rounded),
            tooltip: 'Copiar backup',
            onPressed: _copiarTudo,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configurações',
            onPressed: _abrirConfig,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _criarProjeto,
        tooltip: 'Novo projeto',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (_buscando)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: TextField(
                controller: _ctrlBusca,
                focusNode: _focoBusca,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: 'Buscar em tudo (projetos, tarefas, ideias)…',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          if (!_buscando && _recentes.isNotEmpty) _PrateleiraRecentes(
            projetos: _recentes,
            onAbrir: _abrirProjeto,
          ),
          Expanded(
            child: Builder(builder: (ctx) {
              if (_projetos.isEmpty) return const _Vazio();
              final q = _ctrlBusca.text.trim().toLowerCase();
              // Lupa global: com termo, mostra resultados de PROJETOS (nome) e
              // do CONTEÚDO das caixinhas (Tarefas + Ideias). Sem termo, a
              // lista normal de projetos (arrastável).
              if (_buscando && q.isNotEmpty) return _resultadosBusca(q);
              final visiveis = _projetos;
              final compacto = temaController.compacto;
              // Seções: projetos em andamento primeiro, depois os demais.
              final ativos = visiveis.where((p) => p.emAndamento).toList();
              final outros = visiveis.where((p) => !p.emAndamento).toList();
              final temSecoes = ativos.isNotEmpty;
              final linhas = <Object>[];
              if (temSecoes) {
                linhas.add('EM ANDAMENTO · ${ativos.length}');
                linhas.addAll(ativos);
                if (outros.isNotEmpty) {
                  linhas.add('OUTROS · ${outros.length}');
                  linhas.addAll(outros);
                }
              } else {
                linhas.addAll(outros);
              }
              final app =
                  Theme.of(context).extension<AppCores>() ?? AppCores.azul;
              return ReorderableListView.builder(
                padding: EdgeInsets.fromLTRB(
                    16, compacto ? 6 : 12, 16, 150),
                itemCount: linhas.length,
                buildDefaultDragHandles: false,
                onReorderItem:
                    temSecoes ? _reordenarComSecoes : _reordenar,
                itemBuilder: (_, i) {
                  final item = linhas[i];
                  if (item is String) {
                    // Cabeçalho de seção (não é arrastável).
                    final ehAndamento = item.startsWith('EM ANDAMENTO');
                    return Padding(
                      key: ValueKey('sec-$item'),
                      padding: EdgeInsets.fromLTRB(
                          2, compacto ? 8 : 14, 2, 6),
                      child: Text(
                        item,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: ehAndamento
                              ? app.fab
                              : app.textoUI.withValues(alpha: 0.55),
                        ),
                      ),
                    );
                  }
                  final p = item as Projeto;

                  Future<void> onTapProjeto() => _abrirProjeto(p);

                  if (app.neumorfico) {
                    return Padding(
                      key: ValueKey(p.id),
                      padding: EdgeInsets.only(bottom: compacto ? 8 : 16),
                      child: Caixa3D(
                        cor: app.projetoCard,
                        corInicio: app.projetoCard,
                        corFim: app.projetoCardFim,
                        raio: 18,
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: onTapProjeto,
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 10, 10, 10),
                              child: Row(
                                children: [
                                  q.isNotEmpty
                                      ? Icon(Icons.drag_indicator,
                                          color: app.projetoTxt
                                              .withValues(alpha: 0.5))
                                      : ReorderableDragStartListener(
                                          index: i,
                                          child: Icon(Icons.drag_indicator,
                                              color: app.projetoTxt
                                                  .withValues(alpha: 0.5)),
                                        ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      p.nome,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        color: app.projetoTxt,
                                      ),
                                    ),
                                  ),
                                  BotaoNeum(
                                    raio: 999,
                                    padding: const EdgeInsets.all(7),
                                    corInicio: app.projetoCard,
                                    corFim: app.projetoCardFim,
                                    tooltip: p.emAndamento
                                        ? 'Parar (não está mais em andamento)'
                                        : 'Marcar como em andamento',
                                    onTap: () => _alternarAndamento(p),
                                    child: Icon(
                                        p.emAndamento
                                            ? Icons.check_box
                                            : Icons.check_box_outline_blank,
                                        size: 17,
                                        color: p.emAndamento
                                            ? const Color(0xFF4ADE80)
                                            : app.projetoTxt),
                                  ),
                                  const SizedBox(width: 10),
                                  BotaoNeum(
                                    raio: 999,
                                    padding: const EdgeInsets.all(7),
                                    corInicio: app.projetoCard,
                                    corFim: app.projetoCardFim,
                                    tooltip: 'Renomear',
                                    onTap: () => _renomear(p),
                                    child: Icon(Icons.edit_outlined,
                                        size: 17, color: app.projetoTxt),
                                  ),
                                  const SizedBox(width: 10),
                                  BotaoNeum(
                                    raio: 999,
                                    padding: const EdgeInsets.all(7),
                                    corInicio: app.projetoCard,
                                    corFim: app.projetoCardFim,
                                    tooltip: 'Excluir',
                                    onTap: () => _excluir(p),
                                    child: Icon(Icons.delete_outline,
                                        size: 17,
                                        color: Colors.redAccent
                                            .withValues(alpha: 0.85)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                // Temas planos (Azul, Escuro, Bege e Claude): cartão na cor
                // do tema (no Bege, a mesma cor das caixinhas) com o nome +
                // bolinhas. No Claude, vira "linha": borda de 1px, sem
                // sombras, e o projeto em andamento ganha uma BARRA TERRACOTA
                // à esquerda com o "v" terracota (em vez de verde).
                // No Bege, o check de "em andamento" fica como o quadradinho
                // dentro das caixinhas: bolinha PRETA com "v" bege.
                final ehBege = app == AppCores.bege;
                // No Claude: bolinhas invisíveis (ícones apagados), borda
                // 1px #2A2A2B e acento terracota no "em andamento".
                final ehClaude = app == AppCores.claude;
                final arrastarCor = ehClaude
                    ? app.projetoTxt.withValues(alpha: 0.45)
                    : app.projetoTxt;
                final txtCor = app.projetoTxt;
                final bolaCor = app.notaFim;
                final iconeCor = ehClaude
                    ? app.projetoTxt.withValues(alpha: 0.45)
                    : app.projetoTxt;
                final corBolaAndamento = ehBege
                    ? Colors.black
                    : (ehClaude ? Colors.transparent : bolaCor);
                final corCheckAndamento = ehBege
                    ? app.notaInicio
                    : (ehClaude
                        ? app.fab
                        : const Color(0xFF4ADE80));

                return Padding(
                  key: ValueKey(p.id),
                  padding: EdgeInsets.only(bottom: compacto ? 5 : 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: app.projetoCard,
                      borderRadius: BorderRadius.circular(ehClaude ? 10 : 14),
                      border: ehClaude
                          ? Border(
                              // Barra terracota à esquerda = projeto
                              // em andamento.
                              left: BorderSide(
                                color: p.emAndamento ? app.fab : app.notaBorda,
                                width: p.emAndamento ? 3 : 1,
                              ),
                              top: const BorderSide(
                                  color: Color(0xFF2A2A2B)),
                              right: const BorderSide(
                                  color: Color(0xFF2A2A2B)),
                              bottom: const BorderSide(
                                  color: Color(0xFF2A2A2B)),
                            )
                          : Border.all(
                              color: app.projetoTxt.withValues(alpha: 0.08),
                            ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 10, 4),
                      child: Row(
                        children: [
                          q.isNotEmpty
                              ? Icon(Icons.drag_indicator, color: arrastarCor)
                              : ReorderableDragStartListener(
                                  index: i,
                                  child: Icon(Icons.drag_indicator,
                                      color: arrastarCor),
                                ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: onTapProjeto,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  p.nome,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: txtCor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: p.emAndamento
                                  ? corBolaAndamento
                                  : bolaCor,
                            ),
                            child: IconButton(
                              icon: Icon(
                                  p.emAndamento
                                      ? Icons.check
                                      : Icons.check_box_outline_blank,
                                  size: 18),
                              color: p.emAndamento
                                  ? corCheckAndamento
                                  : iconeCor,
                              tooltip: p.emAndamento
                                  ? 'Parar (não está mais em andamento)'
                                  : 'Marcar como em andamento',
                              onPressed: () => _alternarAndamento(p),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: bolaCor,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              color: iconeCor,
                              tooltip: 'Renomear',
                              onPressed: () => _renomear(p),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: bolaCor,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              color: iconeCor,
                              tooltip: 'Excluir',
                              onPressed: () => _excluir(p),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
            }),
          ),
        ],
      ),
      ),
    );
  }
}

/// Um resultado da busca global: a caixinha [nota] achada dentro de [projeto]
/// na aba [aba] (0 = Tarefas, 1 = Ideias), com um [trecho] para exibir.
class _ResultadoBusca {
  _ResultadoBusca({
    required this.projeto,
    required this.aba,
    required this.nota,
    required this.trecho,
  });

  final Projeto projeto;
  final int aba;
  final Nota nota;
  final String trecho;
}

Future<String?> _pedirNome(BuildContext context,
    {required String titulo, String inicial = ''}) {
  final ctrl = TextEditingController(text: inicial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(titulo),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Nome do projeto'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancelar')),
        TextButton(
            onPressed: () => Navigator.pop(context, capitalizarInicial(ctrl.text)),
            child: const Text('Criar')),
      ],
    ),
  );
}

/// Exporta todos os projetos num arquivo .json e abre o menu de
/// compartilhamento (salvar no Drive, enviar, etc.).
Future<void> _exportarBackup(BuildContext context) async {
  try {
    final json = await Storage.instance.exportarJson();
    final dir = await getTemporaryDirectory();
    final agora = DateTime.now();
    String dois(int n) => n.toString().padLeft(2, '0');
    final nome = 'adm-projetos-backup-${agora.year}-${dois(agora.month)}-'
        '${dois(agora.day)}-${dois(agora.hour)}${dois(agora.minute)}.json';
    final f = File('${dir.path}/$nome');
    await f.writeAsString(json);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path)],
      subject: 'Backup ADM-projetos',
      text: 'Backup dos seus projetos do ADM-projetos.',
    ));
  } catch (e) {
    if (context.mounted) mostrarAviso(context, 'Não foi possível exportar: $e');
  }
}

/// Lê um arquivo de backup (.json) e restaura os projetos.
Future<void> _importarBackup(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final res = await FilePicker.platform.pickFiles();
  if (res == null || res.files.isEmpty) return;
  final path = res.files.single.path;
  if (path == null) return;

  List<Projeto> novos;
  try {
    final dados = jsonDecode(await File(path).readAsString()) as List;
    novos = dados
        .map((e) => Projeto.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          content: Text('Arquivo inválido: não é um backup do ADM-projetos.')));
    return;
  }
  if (novos.isEmpty) {
    if (context.mounted) mostrarAviso(context, 'O arquivo não tem nenhum projeto.');
    return;
  }
  if (!context.mounted) return;

  final acao = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Importar backup?'),
      content: Text('O arquivo tem ${novos.length} projeto(s).'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        TextButton(
            onPressed: () => Navigator.pop(context, 'somar'),
            child: const Text('Somar ao que existe')),
        TextButton(
            onPressed: () => Navigator.pop(context, 'substituir'),
            child: const Text('Substituir tudo')),
      ],
    ),
  );
  if (acao == null) return;

  if (acao == 'substituir') {
    await Storage.instance.substituir(novos);
  } else {
    final atuais = await Storage.instance.carregar();
    final ids = atuais.map((p) => p.id).toSet();
    final mesclados = [
      ...atuais,
      ...novos.where((p) => !ids.contains(p.id)),
    ];
    await Storage.instance.substituir(mesclados);
  }
  if (!context.mounted) return;
  mostrarAviso(context, 'Backup importado com sucesso!');
  Navigator.of(context).pop('atualizado');
}

/// Mostra o estado bruto dos arquivos de dados (para diagnosticar "apagou
/// tudo"): tamanhos, se parseiam e quantos projetos cada um tem.
Future<void> _mostrarDiagnostico(BuildContext context) async {
  final texto = await Storage.instance.diagnostico();
  if (!context.mounted) return;
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Diagnóstico de dados'),
      content: SingleChildScrollView(
        child: SelectableText(
          texto,
          style: const TextStyle(fontSize: 11, height: 1.5),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}

/// Folha de configurações (aberta pela engrenagem): tema e tamanho da fonte.
class _ConfigSheet extends StatelessWidget {
  const _ConfigSheet();

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // (A alça de arraste vem do showModalBottomSheet showDragHandle.)
            const Text('Configurações',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text('Tema',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            ListenableBuilder(
              listenable: temaController,
              builder: (context, _) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in Modo.values)
                      ChoiceChip(
                        label: Text(m.rotulo),
                        selected: temaController.modo == m,
                        onSelected: (_) => temaController.definir(m),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            const Text('Tamanho da fonte',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            ListenableBuilder(
              listenable: temaController,
              builder: (context, _) {
                return SegmentedButton<ModoFonte>(
                  segments: [
                    for (final f in ModoFonte.values)
                      ButtonSegment(
                        value: f,
                        label: Text(f.rotulo),
                      ),
                  ],
                  selected: {temaController.fonte},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) =>
                      temaController.definirFonte(s.first),
                );
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Ajusta texto e ícones do app.',
              style: TextStyle(color: s.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Text('Densidade',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            ListenableBuilder(
              listenable: temaController,
              builder: (context, _) {
                return SegmentedButton<Densidade>(
                  segments: [
                    for (final d in Densidade.values)
                      ButtonSegment(
                        value: d,
                        label: Text(d.rotulo),
                      ),
                  ],
                  selected: {temaController.densidade},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) =>
                      temaController.definirDensidade(s.first),
                );
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Compacto aproxima os cartões e deixa mais conteúdo por tela '
              '(vale também para as caixinhas do projeto).',
              style: TextStyle(color: s.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Text('Barra de ferramentas das caixinhas',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.reorder, size: 18),
              label: const Text('Mudar ordem dos botões'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OrdemBarraScreen()),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Reordene os botões da barra (copiar, limpar, excluir, link…) '
              'para todas as caixinhas.',
              style: TextStyle(color: s.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Text('Backup',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('Exportar arquivo'),
                    onPressed: () => _exportarBackup(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Importar arquivo'),
                    onPressed: () => _importarBackup(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Salve ou restaure seus projetos num arquivo (bom para trocar '
              'de celular).',
              style: TextStyle(color: s.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.health_and_safety_outlined, size: 18),
              label: const Text('Diagnóstico de dados'),
              onPressed: () => _mostrarDiagnostico(context),
            ),
            const SizedBox(height: 16),
            const Text('Nuvem',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: SyncService.instance,
              builder: (context, _) {
                final sync = SyncService.instance;
                if (!sync.conectado) {
                  return OutlinedButton.icon(
                    icon: const Icon(Icons.login, size: 18),
                    label: const Text('Entrar com Google'),
                    onPressed: () => _entrarGoogle(context),
                  );
                }
                final ok = sync.status == 'Sincronizado';
                final ocupado = sync.status == 'Enviando…' ||
                    sync.status == 'Baixando…' ||
                    sync.status == 'Conectando…';
                final erro = sync.status == 'Erro';
                final corStatus = ok
                    ? const Color(0xFF4ADE80)
                    : (erro ? Colors.redAccent : s.onSurfaceVariant);
                final icone = ok
                    ? Icons.cloud_done_outlined
                    : (erro
                        ? Icons.cloud_off_outlined
                        : Icons.cloud_outlined);
                String texto = sync.status;
                if (ok && sync.ultimoEnvio != null) {
                  final h = sync.ultimoEnvio!.hour.toString().padLeft(2, '0');
                  final m = sync.ultimoEnvio!.minute.toString().padLeft(2, '0');
                  texto = 'Enviado às $h:$m';
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(icone, size: 18, color: corStatus),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Conectado como ${sync.usuario!.email ?? ''}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: sync.sair,
                          child: const Text('Sair'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      texto,
                      style: TextStyle(
                        color: corStatus,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (sync.nuvemMaisNova) ...[
                      const SizedBox(height: 6),
                      Text(
                        'A nuvem tem uma versão mais nova que a deste celular. '
                        'Toque em "Baixar da nuvem" para trazê-la.',
                        style: TextStyle(
                            color: s.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                    if (erro && sync.ultimaMensagem != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        sync.ultimaMensagem!,
                        style: TextStyle(
                            color: s.onSurfaceVariant, fontSize: 11),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.cloud_download_outlined,
                                size: 18),
                            label: const Text('Baixar da nuvem'),
                            onPressed: ocupado
                                ? null
                                : () => _confirmarBaixar(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.cloud_upload_outlined,
                                size: 18),
                            label: const Text('Enviar para a nuvem'),
                            onPressed: ocupado ? null : sync.enviarAgora,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'A nuvem é um backup manual: nada sobe ou desce sozinho. '
                      '"Enviar" guarda o que está neste celular; "Baixar" '
                      'substitui o que está aqui pelo da nuvem (ex.: ao trocar '
                      'de celular).',
                      style:
                          TextStyle(color: s.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirma antes de baixar da nuvem (a operação SUBSTITUI os projetos deste
/// celular). Só é oferecida nas Configurações, sem nenhuma caixinha aberta.
Future<void> _confirmarBaixar(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Baixar da nuvem?'),
      content: const Text(
        'Os projetos deste celular serão SUBSTITUÍDOS pelos que estão na '
        'nuvem. Use ao trocar de celular ou para restaurar um backup.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
        TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Baixar')),
      ],
    ),
  );
  if (ok == true) await SyncService.instance.baixarDaNuvem();
}

/// Faz login com o Google. Se o Firebase ainda não estiver configurado,
/// mostra um aviso amigável.
Future<void> _entrarGoogle(BuildContext context) async {
  try {
    await SyncService.instance.entrarComGoogle();
  } catch (e) {
    if (context.mounted) {
      mostrarAviso(
        context,
        'Não foi possível entrar. O Firebase ainda não está configurado '
        'neste aparelho.',
      );
    }
  }
}

class _Vazio extends StatelessWidget {
  const _Vazio();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icono.png',
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
            const SizedBox(height: 16),
            const Text('Nenhum projeto ainda',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Toque no + para criar um projeto e começar a anotar suas ideias.',
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Prateleira rolante "Últimos abertos": os [Storage.maxRecentes] projetos
/// mais recentemente abertos, em cartões compactos com contagem de caixinhas
/// e barra de progresso (feitas/total). Visual acompanha o tema (no Claude,
/// borda 1px estilo terminal).
class _PrateleiraRecentes extends StatelessWidget {
  const _PrateleiraRecentes({
    required this.projetos,
    required this.onAbrir,
  });

  final List<Projeto> projetos;
  final ValueChanged<Projeto> onAbrir;

  @override
  Widget build(BuildContext context) {
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.azul;
    final ehClaude = app == AppCores.claude;
    final compacto = temaController.compacto;
    final rotuloCor = app.textoUI.withValues(alpha: 0.55);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, compacto ? 6 : 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'RECENTES',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: rotuloCor,
                ),
              ),
              const Spacer(),
              // Data do último envio à nuvem (mesma linha do rótulo).
              ListenableBuilder(
                listenable: SyncService.instance,
                builder: (context, _) {
                  final envio = SyncService.instance.ultimoEnvio;
                  final data = envio == null
                      ? 'nunca enviado'
                      : 'último envio '
                          '${envio.day.toString().padLeft(2, '0')}/'
                          '${envio.month.toString().padLeft(2, '0')}/'
                          '${(envio.year % 100).toString().padLeft(2, '0')}';
                  return Text(
                    data,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: rotuloCor,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: compacto ? 58 : 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: projetos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final p = projetos[i];
                final total = p.tarefas.length + p.futuro.length;
                final feitas = (p.tarefas + p.futuro)
                    .where((n) => n.concluida)
                    .length;
                final fracao = total == 0 ? 0.0 : feitas / total;

                Widget cartao = Padding(
                  padding: EdgeInsets.all(compacto ? 6 : 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: compacto ? 11.5 : 12.5,
                          color: app.projetoTxt,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$total caixinhas',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: app.projetoTxt.withValues(alpha: 0.55),
                        ),
                      ),
                      const Spacer(),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: Container(
                          height: 3,
                          color: ehClaude
                              ? const Color(0xFF2A2A2B)
                              : app.projetoTxt.withValues(alpha: 0.15),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: fracao,
                            child: Container(color: app.fab),
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                if (app.neumorfico) {
                  cartao = Caixa3D(
                    cor: app.projetoCard,
                    corInicio: app.projetoCard,
                    corFim: app.projetoCardFim,
                    raio: 12,
                    child: cartao,
                  );
                } else {
                  cartao = Container(
                    width: 130,
                    decoration: BoxDecoration(
                      color: app.projetoCard,
                      borderRadius: BorderRadius.circular(ehClaude ? 10 : 14),
                      border: ehClaude
                          ? const Border(
                              top: BorderSide(color: Color(0xFF2A2A2B)),
                              left: BorderSide(color: Color(0xFF2A2A2B)),
                              right: BorderSide(color: Color(0xFF2A2A2B)),
                              bottom: BorderSide(color: Color(0xFF2A2A2B)),
                            )
                          : Border.all(
                              color: app.projetoTxt.withValues(alpha: 0.08),
                            ),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(ehClaude ? 10 : 14),
                        onTap: () => onAbrir(p),
                        child: cartao,
                      ),
                    ),
                  );
                }
                return cartao;
              },
            ),
          ),
        ],
      ),
    );
  }
}