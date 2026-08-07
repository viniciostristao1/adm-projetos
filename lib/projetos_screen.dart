import 'package:flutter/material.dart';

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
            const Text('ADM-projetos'),
          ],
        ),
        centerTitle: false,
        actions: [
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
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              itemCount: _projetos.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final p = _projetos[i];
                final app = Theme.of(context).extension<AppCores>() ?? AppCores.luz;
                return Card(
                  color: app.projetoCard,
                  child: ListTile(
                    leading: Icon(Icons.folder_outlined, color: app.projetoTxt),
                    title: Text(p.nome,
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: app.projetoTxt)),
                    subtitle: Text(
                        '${p.notas.length} ${p.notas.length == 1 ? 'caixa' : 'caixas'}',
                        style: TextStyle(
                            color: app.projetoTxt.withValues(alpha: 0.7))),
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
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProjetoScreen(projeto: p),
                        ),
                      );
                      await _salvar();
                      if (mounted) setState(() {});
                    },
                  ),
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

/// Folha de configurações (aberta pela engrenagem): tema claro/escuro.
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
            const SizedBox(height: 8),
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
            const SizedBox(height: 4),
            Text(
              'Escolha o tema: Claro, Escuro ou Bege.',
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