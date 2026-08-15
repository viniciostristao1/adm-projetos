import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
  final TextEditingController _ctrlBusca = TextEditingController();
  final FocusNode _focoBusca = FocusNode();
  bool _buscando = false;

  @override
  void initState() {
    super.initState();
    Storage.instance.carregar().then((p) {
      if (mounted) setState(() => _projetos = p);
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

  Future<void> _aoMudarStorage() async {
    // IMPORTANTE: sem List.of — a tela precisa apontar para a MESMA lista
    // interna do Storage; copiar desliga as edições do salvamento (bug de
    // "dados que somem").
    final p = await Storage.instance.carregar();
    if (mounted) setState(() => _projetos = p);
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
      await _salvar();
      if (!mounted) return;
      mostrarAvisoAcao(
        context,
        'Projeto excluído',
        'Desfazer',
        () {
          setState(() => _projetos.insert(
              idx > _projetos.length ? _projetos.length : idx, p));
          _salvar();
        },
      );
    }
  }

  /// Abre/fecha o campo de busca por nome dos projetos.
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
              'ADM-projetos',
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
                  hintText: 'Buscar projeto por nome…',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          Expanded(
            child: Builder(builder: (ctx) {
              final q = _ctrlBusca.text.trim().toLowerCase();
              final visiveis = q.isEmpty
                  ? _projetos
                  : _projetos
                      .where((p) => p.nome.toLowerCase().contains(q))
                      .toList();
              if (_projetos.isEmpty) return const _Vazio();
              if (visiveis.isEmpty) {
                return const Center(
                    child: Text('Nenhum projeto encontrado.',
                        style: TextStyle(color: Colors.grey)));
              }
              return ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 150),
                itemCount: visiveis.length,
                buildDefaultDragHandles: false,
                onReorderItem: _reordenar,
                itemBuilder: (_, i) {
                  final p = visiveis[i];
                  final app =
                      Theme.of(context).extension<AppCores>() ?? AppCores.azul;

                  Future<void> onTapProjeto() async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProjetoScreen(projeto: p),
                      ),
                    );
                    await _salvar();
                    if (mounted) setState(() {});
                  }

                  if (app.neumorfico) {
                    return Padding(
                      key: ValueKey(p.id),
                      padding: const EdgeInsets.only(bottom: 16),
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

                // Temas planos (Azul, Escuro e Bege): cartão na cor do tema
                // (no Bege, a mesma cor das caixinhas) com o nome + bolinhas.
                final arrastarCor = app.projetoTxt;
                final txtCor = app.projetoTxt;
                final bolaCor = app.notaFim;
                final iconeCor = app.projetoTxt;

                return Padding(
                  key: ValueKey(p.id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: app.projetoCard,
                      borderRadius: BorderRadius.circular(14),
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
                              color: bolaCor,
                            ),
                            child: IconButton(
                              icon: Icon(
                                  p.emAndamento
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank,
                                  size: 18),
                              color: p.emAndamento
                                  ? const Color(0xFF4ADE80)
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
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
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