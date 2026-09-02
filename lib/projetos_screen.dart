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
import 'lembretes.dart';
import 'models.dart';
import 'projeto_screen.dart';
import 'storage.dart';
import 'sync_service.dart';
import 'tema.dart';
import 'versao.dart';

const Map<String, Color> mapaCoresPasta = {
  'azul': Color(0xFF3B82F6),
  'amarelo': Color(0xFFEAB308),
  'vermelho': Color(0xFFEF4444),
  'verde': Color(0xFF22C55E),
  'roxo': Color(0xFFA855F7),
  'marrom': Color(0xFF8D6E63),
  'bege': Color(0xFFD7B98E),
};

Color? corPastaDeNome(String? nome) => nome == null ? null : mapaCoresPasta[nome];

Color? corEfetivaPasta(Projeto p, AppCores app) {
  if (p.emAndamento) return app.fab;
  return corPastaDeNome(p.cor);
}

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
    // ⚠️ NÃO ajustar `newIndex` (o antigo `if (newIndex > oldIndex) newIndex--`):
    // esta versão do Flutter usa `onReorderItem`, que JÁ entrega o newIndex
    // ajustado para o item removido. O ajuste a mais fazia mover PARA BAIXO
    // cair em `newIndex == oldIndex` e não mover (só mover para cima funcionava).
    if (newIndex == oldIndex) return;
    // Início da seção do item arrastado (só posições de projeto acima dele).
    var ini = oldIndex;
    while (ini > 0 && linhas[ini - 1] is Projeto) {
      ini--;
    }
    // ⚠️ NÃO rejeitar por [ini, fim] (o antigo `if (newIndex > fim) return`):
    // o cartão arrastado (60px) é mais ALTO que o cabeçalho da próxima seção
    // (30px), então ao soltar no FIM da seção o SDK devolve o índice DO
    // CABEÇALHO seguinte (fora de [ini, fim]) — e o return fazia a pasta
    // VOLTAR. Como a seção EM ANDAMENTO é seguida por um cabeçalho, isso
    // travava todo reorder dentro dela (o OUTROS, última seção, não tinha
    // cabeçalho depois → funcionava). Deixar o `dest` fazer o clamp mantém a
    // pasta na PRÓPRIA seção (arrastar um pouco além gruda na borda, não volta).
    final grupo = alvo.emAndamento ? ativos : outros;
    final grupoSem = grupo.where((p) => p.id != alvo.id).toList();
    final dest = (newIndex - ini).clamp(0, grupoSem.length);
    final novoGrupo = [...grupoSem]..insert(dest, alvo);
    var gi = 0;
    final reordenado = <Projeto>[
      for (final p in _projetos)
        if (grupo.any((g) => g.id == p.id)) novoGrupo[gi++] else p,
    ];
    // ⚠️ MUTAR a lista NO LUGAR (clear+addAll), NÃO reatribuir `_projetos`:
    // ela é a MESMA referência da lista interna do Storage (carregar() a
    // devolve e a tela faz `_projetos = p`). Reatribuir quebrava esse vínculo
    // → `salvar()` gravava a ordem ANTIGA do Storage e o `notifyListeners()`
    // disparava `_aoMudarStorage`, que reapontava `_projetos` para a lista
    // interna (antiga) → a pasta "voltava" ao lugar. Como só quebrava com
    // seções (o `_reordenar` plano já muta no lugar), o sintoma era: com um
    // projeto EM ANDAMENTO, as pastas de OUTROS não saíam do lugar.
    setState(() {
      _projetos
        ..clear()
        ..addAll(reordenado);
    });
    _salvar();
  }

  Future<void> _copiarTudo() async {
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
    // Bloco final (não legível) com o backup COMPLETO em JSON: o "Restaurar de
    // um texto colado" usa isto para reconstruir TUDO fielmente (caixinhas
    // separadas, comentários, links, checkbox). A parte de cima segue legível.
    buf
      ..writeln()
      ..writeln(marcadorBackupJson)
      ..write(await Storage.instance.exportarJson());
    final texto = buf.toString();
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    mostrarAviso(context,
        'Backup copiado — restaura tudo (caixinhas, comentários, links).');
  }

  Future<void> _abrirConfig() async {
    await showModalBottomSheet<String>(
      context: context,
      // showDragHandle: a alça no topo vira um alvo de arraste CONFIÁVEL para
      // fechar a folha puxando para baixo — antes, o SingleChildScrollView do
      // conteúdo engolia o gesto e só dava para sair pelo botão "voltar" do
      // Android. enableDrag já é true por padrão.
      showDragHandle: true,
      // isScrollControlled + maxHeight 90%: sem isso a folha era limitada a
      // ~9/16 da tela e, ao expandir a última seção (Nuvem), as opções caíam
      // abaixo do visível e a rolagem ficava apertada. Agora a folha usa até
      // 90% da altura e o SingleChildScrollView interno rola com folga.
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
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

  /// Abre a folha de "Lembrete rápido" (sininho): escrever + tocar num tempo →
  /// notificação no Android. Também lista os lembretes pendentes para cancelar.
  Future<void> _abrirLembretes() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      // useSafeArea: a folha respeita o topo (barra de status: relógio,
      // bateria, rede) — sem isso, com o teclado aberto ela subia demais e
      // entrava por baixo dessas informações.
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _LembreteSheet(),
    );
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

  /// Envolve o cartão de projeto num Dismissible: arrastar para a ESQUERDA
  /// exclui a pasta (com Desfazer via [_excluirComUndo]).
  Widget _arrastavel(Projeto p, Widget filho) => Dismissible(
        key: ValueKey(p.id),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => _excluirComUndo(p),
        background: Container(
          alignment: Alignment.centerRight,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.only(right: 22),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.delete_outline, color: Colors.redAccent),
        ),
        child: filho,
      );

  Future<void> _renomear(Projeto p) async {
    final nome = await _pedirNome(context, titulo: 'Renomear projeto',
        inicial: p.nome);
    if (nome == null || nome.trim().isEmpty) return;
    setState(() => p.nome = nome.trim());
    await _salvar();
  }

  /// Alterna o "em andamento" do projeto (✓ verde no cartão da lista).
  /// Ao DESMARCAR no projeto, desmarca também as caixinhas marcadas como
  /// feitas lá dentro (espelho nos dois sentidos).
  void _alternarAndamento(Projeto p) {
    setState(() {
      p.emAndamento = !p.emAndamento;
      if (!p.emAndamento) {
        for (final n in [...p.tarefas, ...p.futuro]) {
          n.concluida = false;
        }
      }
    });
    _salvar();
  }

  void _definirCorPasta(Projeto p, String? cor) {
    setState(() => p.cor = cor);
    _salvar();
  }

  Future<void> _mostrarSeletorCor(Projeto p) async {
    final escolha = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final sel = p.cor;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cor da pasta: ${p.nome}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  p.emAndamento
                      ? 'Em andamento: mostra a cor do tema. Sua cor volta ao desmarcar.'
                      : 'Toque numa cor. Segure a pasta para trocar a qualquer hora.',
                  style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _bolhaCor(null, sel == null, ctx),
                    for (final e in mapaCoresPasta.entries) _bolhaCor(e.key, sel == e.key, ctx),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (escolha == '__nenhuma__') {
      _definirCorPasta(p, null);
    } else if (escolha != null) {
      _definirCorPasta(p, escolha);
    }
  }

  Widget _bolhaCor(String? nome, bool selecionado, BuildContext ctx) {
    final isNone = nome == null;
    final cor = isNone ? null : mapaCoresPasta[nome];
    return GestureDetector(
      onTap: () => Navigator.pop(ctx, isNone ? '__nenhuma__' : nome),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isNone ? Colors.transparent : cor,
              border: Border.all(
                color: selecionado
                    ? Theme.of(ctx).colorScheme.primary
                    : (isNone ? Colors.grey.shade400 : Colors.transparent),
                width: selecionado ? 2.2 : 1.2,
              ),
            ),
            child: isNone
                ? Icon(Icons.block, size: 16, color: Colors.grey.shade500)
                : selecionado
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : null,
          ),
          const SizedBox(height: 3),
          Text(isNone ? 'sem cor' : nome!,
              style: TextStyle(fontSize: 10, fontWeight: selecionado ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }

  /// Remoção SEGURA + Desfazer, sem diálogo. Único ponto de exclusão de projeto:
  /// usado pelo arrastar-para-excluir (Dismissible) e pelo botão de excluir de
  /// DENTRO do projeto (que confirma e devolve 'excluir' para cá).
  Future<void> _excluirComUndo(Projeto p) async {
    final idx = _projetos.indexOf(p);
    if (idx < 0) return;
    setState(() => _projetos.remove(p));
    // Exclusão EXPLÍCITA do último projeto: autoriza a gravação da lista vazia
    // (a guarda anti-esvaziamento do Storage bloqueia o resto).
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

  /// Abre o projeto (também registra na prateleira "Últimos abertos").
  Future<void> _abrirProjeto(Projeto p) async {
    await Storage.instance.registrarAbertura(p.id);
    if (!mounted) return;
    final r = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProjetoScreen(projeto: p)),
    );
    if (!mounted) return;
    if (r == 'excluir') {
      await _excluirComUndo(p);
      return;
    }
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
    final res = await Navigator.push(
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
    if (!mounted) return;
    if (res == 'excluir') {
      await _excluirComUndo(r.projeto);
      return;
    }
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
    // Também acha LEMBRETES pelo texto escrito (ponto: buscar lembretes junto
    // na busca da home, em vez de uma busca só dentro dos lembretes).
    final lembretes = LembretesService.instance.pendentes
        .where((l) => l.texto.toLowerCase().contains(q))
        .toList();
    if (projetosNome.isEmpty && conteudo.isEmpty && lembretes.isEmpty) {
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
        if (lembretes.isNotEmpty) ...[
          _cabecalhoResultado('LEMBRETES', app),
          for (final l in lembretes) _cartaoLembreteResultado(l, q, app),
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

  /// Data/hora curta de um lembrete ("hoje 14:30", "amanhã 09:00", "23/08 14:30").
  String _quandoBreve(DateTime dt) {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final dia = DateTime(dt.year, dt.month, dt.day);
    final hm = '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    final d = dia.difference(hoje).inDays;
    if (d == 0) return 'hoje $hm';
    if (d == 1) return 'amanhã $hm';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')} $hm';
  }

  /// Card de um lembrete achado na busca; toca → abre a folha de lembretes.
  Widget _cartaoLembreteResultado(Lembrete l, String q, AppCores app) =>
      _cartaoResultado(
        app: app,
        onTap: _abrirLembretes,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(Icons.alarm, size: 18, color: app.fab),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _textoDestacado(
                      l.texto.isEmpty ? '(sem texto)' : l.texto,
                      q,
                      TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                        color: app.projetoTxt,
                      ),
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    Text(_quandoBreve(l.quando),
                        style: TextStyle(
                            fontSize: 11.5,
                            color: app.projetoTxt.withValues(alpha: 0.6))),
                  ],
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
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.azul;
    return Fundo(
      child: Scaffold(
      // Home "sem caixa" (Bege): o fundo da tela inicial fica na cor da caixinha
      // (bege queimado #E0D1B9) e as pastas ficam lisas por cima. Ônix já tem o
      // fundo preto pelo próprio tema.
      backgroundColor: app == AppCores.bege ? app.projetoCard : null,
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
            icon: const Icon(Icons.notifications_none),
            tooltip: 'Lembrete rápido',
            onPressed: _abrirLembretes,
          ),
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

                  final corEfetiva = corEfetivaPasta(p, app);
                  if (app.neumorfico) {
                    Widget card = Caixa3D(
                      cor: app.projetoCard,
                      corInicio: app.projetoCard,
                      corFim: app.projetoCardFim,
                      raio: 18,
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: onTapProjeto,
                          onLongPress: () => _mostrarSeletorCor(p),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
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
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                    if (corEfetiva != null) {
                      card = ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Stack(
                          children: [
                            card,
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              child: Container(width: 4, color: corEfetiva),
                            ),
                          ],
                        ),
                      );
                    }
                    return _arrastavel(
                        p,
                        Padding(
                          padding: EdgeInsets.only(bottom: compacto ? 8 : 16),
                          child: card,
                        ));
                  }

                // Temas planos (Azul, Escuro, Bege e Claude): cartão na cor
                // do tema (no Bege, a mesma cor das caixinhas) com o nome +
                // bolinhas. No Claude, vira "linha": borda de 1px, sem
                // sombras, e o projeto em andamento ganha uma BARRA TERRACOTA
                // à esquerda com o "v" terracota (em vez de verde).
                // No Bege, o check de "em andamento" fica como o quadradinho
                // dentro das caixinhas: bolinha PRETA com "v" bege.
                final ehBege = app == AppCores.bege;
                // No Claude/Terracota: bolinhas invisíveis (ícones apagados),
                // borda 1px #2A2A2B e acento terracota no "em andamento".
                final ehClaude = app == AppCores.claude;
                final ehOnix = app == AppCores.onix;
                // Bege e Ônix: pastas SEM caixa nem borda (linhas lisas sobre o
                // fundo). Os demais temas mantêm o cartão.
                final semCaixa = ehBege || ehOnix;
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
                    : ((ehClaude || ehOnix)
                        ? app.fab
                        : const Color(0xFF4ADE80));

                BoxDecoration? baseDecor;
                if (semCaixa) {
                  baseDecor = null;
                } else if (ehClaude) {
                  baseDecor = BoxDecoration(
                    color: app.projetoCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2A2A2B)),
                  );
                } else {
                  baseDecor = BoxDecoration(
                    color: app.projetoCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: app.projetoTxt.withValues(alpha: 0.08)),
                  );
                }

                Widget cardPlano = Container(
                  decoration: baseDecor,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 10, 4),
                    child: Row(
                      children: [
                        q.isNotEmpty
                            ? Icon(Icons.drag_indicator, color: arrastarCor)
                            : ReorderableDragStartListener(
                                index: i,
                                child: Icon(Icons.drag_indicator, color: arrastarCor),
                              ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: onTapProjeto,
                            onLongPress: () => _mostrarSeletorCor(p),
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
                            color: p.emAndamento ? corBolaAndamento : bolaCor,
                          ),
                          child: IconButton(
                            icon: Icon(
                                p.emAndamento ? Icons.check : Icons.check_box_outline_blank,
                                size: 18),
                            color: p.emAndamento ? corCheckAndamento : iconeCor,
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
                      ],
                    ),
                  ),
                );
                if (corEfetiva != null) {
                  final raio = ehClaude ? 10.0 : 14.0;
                  cardPlano = ClipRRect(
                    borderRadius: BorderRadius.circular(raio),
                    child: Stack(
                      children: [
                        cardPlano,
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: Container(width: 4, color: corEfetiva),
                        ),
                      ],
                    ),
                  );
                }
                return _arrastavel(
                    p,
                    Padding(
                      padding: EdgeInsets.only(bottom: compacto ? 5 : 10),
                      child: cardPlano,
                    ));
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

/// Tela "Restaurar de um texto colado": cola o texto do botão "Copiar backup"
/// (ou um backup em JSON) e reconstrói os projetos. Recuperação de emergência
/// quando não há arquivo exportado nem nuvem.
class RestaurarTextoScreen extends StatefulWidget {
  const RestaurarTextoScreen({super.key});

  @override
  State<RestaurarTextoScreen> createState() => _RestaurarTextoScreenState();
}

class _RestaurarTextoScreenState extends State<RestaurarTextoScreen> {
  final TextEditingController _ctrl = TextEditingController();
  bool _ocupado = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _colar() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text;
    if (t != null && t.isNotEmpty) {
      setState(() => _ctrl.text = t);
    } else if (mounted) {
      mostrarAviso(context, 'A área de transferência está vazia.');
    }
  }

  Future<void> _restaurar() async {
    if (_ocupado) return;
    final projetos = projetosDeBackupColado(_ctrl.text);
    if (projetos.isEmpty) {
      mostrarAviso(context,
          'Não reconheci nenhum projeto nesse texto. Cole o texto do botão '
          '"Copiar backup" (ou um backup em JSON).');
      return;
    }
    final acao = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restaurar?'),
        content: Text(
          'Reconheci ${projetos.length} projeto(s). Como quer restaurar?\n\n'
          '"Somar" mantém o que já existe e acrescenta estes. '
          '"Substituir" troca tudo pelos projetos deste texto.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'somar'),
            child: const Text('Somar ao que existe'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'substituir'),
            child: const Text('Substituir tudo'),
          ),
        ],
      ),
    );
    if (acao == null || !mounted) return;
    setState(() => _ocupado = true);
    try {
      if (acao == 'substituir') {
        await Storage.instance.substituir(projetos);
      } else {
        final atuais = await Storage.instance.carregar();
        final ids = atuais.map((p) => p.id).toSet();
        await Storage.instance.substituir([
          ...atuais,
          ...projetos.where((p) => !ids.contains(p.id)),
        ]);
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
    if (!mounted) return;
    mostrarAviso(context, 'Restaurado! ${projetos.length} projeto(s).');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    return Fundo(
      child: Scaffold(
        appBar: AppBar(title: const Text('Restaurar de um texto')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Cole aqui o texto do botão "Copiar backup" (ou um backup em '
                  'JSON) e toque em Restaurar. Cada projeto volta com o texto '
                  'em uma caixinha por aba — você pode separar depois.',
                  style: TextStyle(color: dim, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.content_paste, size: 18),
                      label: const Text('Colar'),
                      onPressed: _colar,
                    ),
                    const Spacer(),
                    if (_ctrl.text.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(_ctrl.clear),
                        child: const Text('Limpar'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Cole o texto do backup aqui…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: _ocupado
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restore),
                  label: const Text('Restaurar'),
                  onPressed: _ocupado ? null : _restaurar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Folha de configurações (aberta pela engrenagem): seções expansíveis —
/// toca na seção (Tema, Fonte, Densidade, Barra, Backup, Nuvem) e ela abre
/// com as opções.
class _ConfigSheet extends StatelessWidget {
  const _ConfigSheet();

  /// Estilo padrão das seções: sem divisórias (fica mais limpo na folha).
  ExpansionTile _sec({
    required IconData icone,
    required String titulo,
    String? subtitulo,
    bool inicialmenteAberta = false,
    required List<Widget> children,
  }) {
    final semBorda = const RoundedRectangleBorder();
    return ExpansionTile(
      leading: Icon(icone, size: 22),
      title: Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      subtitle: subtitulo == null
          ? null
          : Text(subtitulo, style: const TextStyle(fontSize: 12)),
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      shape: semBorda,
      collapsedShape: semBorda,
      initiallyExpanded: inicialmenteAberta,
      children: children,
    );
  }

  Widget _dica(String texto, Color cor) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          texto,
          style: TextStyle(color: cor, fontSize: 12),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final dim = s.onSurfaceVariant;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // (A alça de arraste vem do showModalBottomSheet showDragHandle.)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text('Configurações',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),

            // ================= Tema =================
            _sec(
              icone: Icons.palette_outlined,
              titulo: 'Tema',
              subtitulo: temaController.modo.rotulo,
              children: [
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
              ],
            ),

            // ================= Tamanho da fonte =================
            _sec(
              icone: Icons.format_size,
              titulo: 'Tamanho da fonte',
              subtitulo: temaController.fonte.rotulo,
              children: [
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
                _dica('Ajusta texto e ícones do app.', dim),
              ],
            ),

            // ================= Densidade =================
            _sec(
              icone: Icons.density_small,
              titulo: 'Densidade',
              subtitulo: temaController.densidade.rotulo,
              children: [
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
                _dica(
                  'Compacto aproxima os cartões e deixa mais conteúdo por '
                  'tela (vale também para as caixinhas do projeto).',
                  dim,
                ),
              ],
            ),

            // ================= Barra de ferramentas =================
            _sec(
              icone: Icons.reorder,
              titulo: 'Barra de ferramentas',
              subtitulo: 'Ordem dos botões das caixinhas',
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Mudar ordem dos botões'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const OrdemBarraScreen()),
                  ),
                ),
                _dica(
                  'Reordene os botões da barra (copiar, limpar, excluir, '
                  'link…) para todas as caixinhas.',
                  dim,
                ),
              ],
            ),

            // ================= Backup =================
            _sec(
              icone: Icons.folder_open_outlined,
              titulo: 'Backup',
              subtitulo: 'Arquivo + diagnóstico',
              children: [
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
                _dica(
                  'Salve ou restaure seus projetos num arquivo (bom para '
                  'trocar de celular).',
                  dim,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.content_paste_go_outlined, size: 18),
                  label: const Text('Restaurar de um texto colado'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RestaurarTextoScreen()),
                  ),
                ),
                _dica(
                  'Recupera projetos a partir do texto do botão "Copiar backup" '
                  '(ou de um backup em JSON) — útil se não houver arquivo nem '
                  'nuvem.',
                  dim,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.health_and_safety_outlined, size: 18),
                  label: const Text('Diagnóstico de dados'),
                  onPressed: () => _mostrarDiagnostico(context),
                ),
              ],
            ),

            // ================= Nuvem =================
            ListenableBuilder(
              listenable: SyncService.instance,
              builder: (context, _) {
                final sync = SyncService.instance;
                final sub = !sync.conectado
                    ? 'Desligado'
                    : sync.usuario!.email ?? 'Conectado';
                return _sec(
                  icone: Icons.cloud_outlined,
                  titulo: 'Nuvem',
                  subtitulo: sub,
                  children: [
                    if (!sync.conectado) ...[
                      OutlinedButton.icon(
                        icon: const Icon(Icons.login, size: 18),
                        label: const Text('Entrar com Google'),
                        onPressed: () => _entrarGoogle(context),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Para guardar seus projetos na nuvem, primeiro entre '
                        'com o Google. Depois aparecem os botões "Enviar" e '
                        '"Baixar".',
                        style: TextStyle(color: dim, fontSize: 12),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Icon(
                            sync.status == 'Sincronizado'
                                ? Icons.cloud_done_outlined
                                : (sync.status == 'Erro'
                                    ? Icons.cloud_off_outlined
                                    : Icons.cloud_outlined),
                            size: 18,
                            color: sync.status == 'Sincronizado'
                                ? const Color(0xFF4ADE80)
                                : (sync.status == 'Erro'
                                    ? Colors.redAccent
                                    : s.onSurfaceVariant),
                          ),
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
                        sync.status == 'Sincronizado' &&
                                sync.ultimoEnvio != null
                            ? 'Enviado às '
                                '${sync.ultimoEnvio!.hour.toString().padLeft(2, '0')}:'
                                '${sync.ultimoEnvio!.minute.toString().padLeft(2, '0')}'
                            : sync.status,
                        style: TextStyle(
                          color: sync.status == 'Sincronizado'
                              ? const Color(0xFF4ADE80)
                              : (sync.status == 'Erro'
                                  ? Colors.redAccent
                                  : s.onSurfaceVariant),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (sync.nuvemMaisNova) ...[
                        const SizedBox(height: 6),
                        Text(
                          'A nuvem tem uma versão mais nova que a deste '
                          'celular. Toque em "Baixar da nuvem" para trazê-la.',
                          style: TextStyle(color: dim, fontSize: 12),
                        ),
                      ],
                      if (sync.status == 'Erro' &&
                          sync.ultimaMensagem != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          sync.ultimaMensagem!,
                          style: TextStyle(color: dim, fontSize: 11),
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
                              onPressed:
                                  sync.status == 'Enviando…' ||
                                          sync.status == 'Baixando…' ||
                                          sync.status == 'Conectando…'
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
                              onPressed:
                                  sync.status == 'Enviando…' ||
                                          sync.status == 'Baixando…' ||
                                          sync.status == 'Conectando…'
                                      ? null
                                      : sync.enviarAgora,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'A nuvem é um backup manual: nada sobe ou desce '
                        'sozinho. "Enviar" guarda o que está neste celular; '
                        '"Baixar" substitui o que está aqui pelo da nuvem. '
                        'Dica: toque em Enviar antes de atualizar ou '
                        'desinstalar o app; ao reinstalar (ou trocar de '
                        'celular), entre com a MESMA conta Google e toque em '
                        'Baixar.',
                        style: TextStyle(color: dim, fontSize: 12),
                      ),
                    ],
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

/// Folha "Lembrete rápido" (sininho da tela inicial): escrever + tocar num
/// tempo → notificação no Android. Mostra também os lembretes pendentes para
/// cancelar. Fluxo mínimo: sininho → escrever → tocar no tempo (3 toques).
class _LembreteSheet extends StatefulWidget {
  const _LembreteSheet();

  @override
  State<_LembreteSheet> createState() => _LembreteSheetState();
}

class _LembreteSheetState extends State<_LembreteSheet> {
  final TextEditingController _ctrl = TextEditingController();
  bool _agendando = false;
  // Tempo "montado" somando os botões da 2ª linha (ponto: somar em vez de
  // agendar direto). Zera após Salvar ou Limpar.
  Duration _somado = Duration.zero;

  static const List<(Duration, String)> _presets = [
    (Duration(minutes: 30), '30 min'),
    (Duration(hours: 2), '2 h'),
    (Duration(hours: 4), '4 h'),
    (Duration(hours: 24), '24 h'),
  ];

  @override
  void initState() {
    super.initState();
    // SEM autofocus de propósito: abrir o teclado junto com a animação da folha
    // deixava a subida "travada"/em dois estágios. A folha sobe limpa; o
    // teclado só aparece quando o usuário toca no campo (transição suave,
    // seguindo o teclado 1:1 pelo Padding do build).
    //
    // Recarrega a lista do disco: pega lembretes REPROGRAMADOS pela notificação
    // enquanto o app estava fechado/em segundo plano (o snooze grava direto no
    // SharedPreferences de outro isolate).
    LembretesService.instance.recarregar();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Agenda [d] (com o texto do campo) e devolve true se deu certo. Robusto: o
  /// `finally` SEMPRE rearma o botão (`_agendando=false`), então nunca fica
  /// travado; um erro de agendamento aparece num diálogo copiável (diagnóstico).
  Future<bool> _agendar(Duration d, String rotulo) async {
    if (_agendando) return false;
    setState(() => _agendando = true);
    try {
      final l = await LembretesService.instance.agendar(_ctrl.text.trim(), d);
      if (l == null) {
        if (mounted) {
          mostrarAviso(context,
              'Ative as notificações do Taskix nas configurações do Android.');
        }
        return false;
      }
      _ctrl.clear();
      if (mounted) mostrarAviso(context, 'Lembrete daqui a $rotulo ⏰');
      return true;
    } catch (e) {
      if (mounted) _mostrarErroAgendar(e);
      return false;
    } finally {
      if (mounted) setState(() => _agendando = false);
    }
  }

  void _mostrarErroAgendar(Object e) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Não consegui agendar o lembrete'),
        content: SingleChildScrollView(
          child: SelectableText(
            'Detalhe do erro (para diagnóstico):\n\n$e',
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar')),
        ],
      ),
    );
  }

  /// Salva o tempo MONTADO na 2ª linha (soma dos botões) como um lembrete. Só
  /// zera a soma se o agendamento REALMENTE deu certo.
  Future<void> _salvarSomado() async {
    if (_somado <= Duration.zero) return;
    final ok = await _agendar(_somado, _humanizar(_somado));
    if (ok && mounted) setState(() => _somado = Duration.zero);
  }

  /// "2 h 30 min", "4 h", "45 min" — texto amigável de uma duração.
  String _humanizar(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0 && m > 0) return '$h h $m min';
    if (h > 0) return '$h h';
    return '$m min';
  }

  /// "Outro" (na 1ª linha, ao lado do 24 h): tempo exato personalizado (minutos
  /// ou horas) → agenda direto. Bom para lembretes rápidos e precisos.
  Future<void> _outro() async {
    final ctrl = TextEditingController();
    var unidade = 'minutos';
    final d = await showDialog<Duration>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Outro tempo'),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 84,
                child: TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'ex.: 45'),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: unidade,
                items: const [
                  DropdownMenuItem(value: 'minutos', child: Text('minutos')),
                  DropdownMenuItem(value: 'horas', child: Text('horas')),
                ],
                onChanged: (v) {
                  if (v != null) setLocal(() => unidade = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                final n = int.tryParse(ctrl.text.trim());
                if (n == null || n <= 0) {
                  Navigator.pop(ctx);
                  return;
                }
                Navigator.pop(
                  ctx,
                  unidade == 'horas'
                      ? Duration(hours: n)
                      : Duration(minutes: n),
                );
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (d == null) return;
    final rotulo = d.inMinutes % 60 == 0 && d.inHours >= 1
        ? '${d.inHours} h'
        : '${d.inMinutes} min';
    await _agendar(d, rotulo);
  }

  String _quando(DateTime dt) {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final dia = DateTime(dt.year, dt.month, dt.day);
    final hm = '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    final difDias = dia.difference(hoje).inDays;
    if (difDias == 0) return 'hoje $hm';
    if (difDias == 1) return 'amanhã $hm';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')} $hm';
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      // Padding SIMPLES (não AnimatedPadding): segue o teclado quadro-a-quadro,
      // sem uma 2ª animação por cima que causava a "travadinha".
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.notifications_active_outlined, size: 20),
                  const SizedBox(width: 8),
                  const Text('Lembrete rápido',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'O que lembrar?',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('Notificar daqui a…',
                  style: TextStyle(
                      color: s.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              // Linha 1 — toca e agenda JÁ. Wrap: cabem todos na linha (quebra
              // p/ a linha de baixo se faltar espaço), sem rolagem horizontal.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _presets)
                    ActionChip(
                      label: Text(p.$2),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed:
                          _agendando ? null : () => _agendar(p.$1, p.$2),
                    ),
                  // "Outro" (tempo exato) — SEM ícone de reticências, p/ caber
                  // na mesma linha dos tempos.
                  ActionChip(
                    label: const Text('Outro'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onPressed: _agendando ? null : _outro,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Linha 2 — SOMA um tempo (cor diferente); mostra data/hora + Salvar.
              Text('Ou monte o tempo (vai somando)',
                  style: TextStyle(
                      color: s.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final p in _presets)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text('+ ${p.$2}'),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          backgroundColor: s.primary.withValues(alpha: 0.14),
                          side:
                              BorderSide(color: s.primary.withValues(alpha: 0.5)),
                          labelStyle: TextStyle(
                              color: s.primary, fontWeight: FontWeight.w700),
                          onPressed: () => setState(() => _somado += p.$1),
                        ),
                      ),
                  ],
                ),
              ),
              if (_somado > Duration.zero) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: s.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: s.primary.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.alarm, size: 20, color: s.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Daqui a ${_humanizar(_somado)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14)),
                            Text(_quando(DateTime.now().add(_somado)),
                                style: TextStyle(
                                    fontSize: 12, color: s.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _somado = Duration.zero),
                        child: const Text('Limpar'),
                      ),
                      FilledButton(
                        onPressed: _agendando ? null : _salvarSomado,
                        child: const Text('Salvar'),
                      ),
                    ],
                  ),
                ),
              ],
              ListenableBuilder(
                listenable: LembretesService.instance,
                builder: (context, _) {
                  final pend = LembretesService.instance.pendentes;
                  if (pend.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 18),
                      Text('AGENDADOS',
                          style: TextStyle(
                              color: s.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      for (final l in pend)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.alarm, size: 20),
                          title: Text(
                            l.texto.isEmpty ? '(sem texto)' : l.texto,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(_quando(l.quando)),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Cancelar lembrete',
                            onPressed: () =>
                                LembretesService.instance.cancelar(l.id),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
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
    if (!context.mounted) return;
    // Mostra o ERRO REAL (copiável) — antes engolíamos tudo como "Firebase não
    // configurado", o que escondia a causa (ex.: provedor Google desativado no
    // Console, cancelado pelo usuário, sem internet).
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Não foi possível entrar'),
        content: SingleChildScrollView(
          child: SelectableText(
            'Detalhe do erro (para diagnóstico):\n\n$e',
            style: const TextStyle(fontSize: 12, height: 1.5),
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
    // Bege/Ônix: a home é "sem caixa" e seu fundo é a própria cor do cartão;
    // então os cartões de recentes usam [notaFim] para não sumirem no fundo.
    final semCaixa = app == AppCores.bege || app == AppCores.onix;
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
              // Último envio à nuvem: ícone de nuvem com flecha para cima +
              // data (terracota no tema Claude Code).
              ListenableBuilder(
                listenable: SyncService.instance,
                builder: (context, _) {
                  final envio = SyncService.instance.ultimoEnvio;
                  final cor = ehClaude
                      ? app.fab
                      : rotuloCor;
                  final data = envio == null
                      ? 'nunca'
                      : '${envio.day.toString().padLeft(2, '0')}/'
                          '${envio.month.toString().padLeft(2, '0')}/'
                          '${(envio.year % 100).toString().padLeft(2, '0')}';
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_upload_outlined,
                        size: 13,
                        color: cor,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        data,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: cor,
                        ),
                      ),
                    ],
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
                      color: semCaixa ? app.notaFim : app.projetoCard,
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