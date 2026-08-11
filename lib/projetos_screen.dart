import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'caixa3d.dart';
import 'cores.dart';
import 'editor.dart';
import 'models.dart';
import 'projeto_screen.dart';
import 'storage.dart';
import 'tema.dart';

/// Página principal: a lista de projetos.
class ProjetosScreen extends StatefulWidget {
  const ProjetosScreen({super.key});

  @override
  State<ProjetosScreen> createState() => _ProjetosScreenState();
}

class _ProjetosScreenState extends State<ProjetosScreen> {
  List<Projeto> _projetos = [];

  @override
  void initState() {
    super.initState();
    Storage.instance.carregar().then((p) {
      if (mounted) setState(() => _projetos = p);
    });
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
        buf.writeln('  --- Futuro ---');
        for (final n in p.futuro) {
          for (final linha in n.texto.split('\n')) {
            buf.writeln('  $linha');
          }
        }
      }
    }
    final texto = buf.toString();
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          const SnackBar(content: Text('Backup copiado (todos os projetos)!')));
  }

  void _abrirConfig() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ConfigSheet(),
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

  Future<void> _renomear(Projeto p) async {
    final nome = await _pedirNome(context, titulo: 'Renomear projeto',
        inicial: p.nome);
    if (nome == null || nome.trim().isEmpty) return;
    setState(() => p.nome = nome.trim());
    await _salvar();
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
      setState(() => _projetos.remove(p));
      await _salvar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          ],
        ),
        centerTitle: false,
        actions: [
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
      body: _projetos.isEmpty
          ? const _Vazio()
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 150),
              itemCount: _projetos.length,
              buildDefaultDragHandles: false,
              onReorderItem: _reordenar,
              itemBuilder: (_, i) {
                final p = _projetos[i];
                final app =
                    Theme.of(context).extension<AppCores>() ?? AppCores.luz;
                final modo = temaController.modo;

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

                if (modo == Modo.claro) {
                  return Padding(
                    key: ValueKey(p.id),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Caixa3D(
                      cor: app.projetoCard,
                      child: Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        color: app.projetoCard,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ListTile(
                          leading: ReorderableDragStartListener(
                            index: i,
                            child: Icon(Icons.drag_indicator,
                                color: app.projetoTxt),
                          ),
                          title: Text(
                            p.nome,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: app.projetoTxt),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit_outlined,
                                    size: 20, color: app.projetoTxt),
                                tooltip: 'Renomear',
                                onPressed: () => _renomear(p),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    size: 20, color: app.projetoTxt),
                                tooltip: 'Excluir',
                                onPressed: () => _excluir(p),
                              ),
                            ],
                          ),
                          onTap: onTapProjeto,
                        ),
                      ),
                    ),
                  );
                }

                final escuro = modo == Modo.escuro;
                final dividir =
                    escuro ? const Color(0xFF333333) : const Color(0xFF8D7255);
                final arrastarCor = escuro ? Colors.white : const Color(0xFF6D4C2F);
                final txtCor = escuro ? Colors.white : const Color(0xFF4A2A0E);
                final bolaCor = escuro ? const Color(0xFF3A3A3A) : const Color(0xFF6D4C2F);
                final iconeCor = Colors.white;

                return Column(
                  key: ValueKey(p.id),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 16, 8),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: Icon(Icons.drag_indicator, color: arrastarCor),
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
                    Divider(height: 1, thickness: 1, color: dividir),
                  ],
                );
              },
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

/// Folha de configurações (aberta pela engrenagem): tema e tamanho da fonte.
class _ConfigSheet extends StatelessWidget {
  const _ConfigSheet();

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
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
                return SegmentedButton<Modo>(
                  segments: const [
                    ButtonSegment(
                      value: Modo.claro,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Claro'),
                    ),
                    ButtonSegment(
                      value: Modo.escuro,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Escuro'),
                    ),
                    ButtonSegment(
                      value: Modo.bege,
                      icon: Icon(Icons.grid_4x4_outlined),
                      label: Text('Bege'),
                    ),
                  ],
                  selected: {temaController.modo},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => temaController.definir(s.first),
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
          ],
        ),
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