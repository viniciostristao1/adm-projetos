import 'package:flutter/material.dart';

import 'models.dart';
import 'projeto_screen.dart';
import 'storage.dart';

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
        title: const Row(
          children: [
            Icon(Icons.lightbulb_outline, size: 22),
            SizedBox(width: 8),
            Text('ADM-projetos'),
          ],
        ),
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
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(p.nome,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${p.notas.length} ${p.notas.length == 1 ? 'caixa' : 'caixas'}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'Renomear',
                          onPressed: () => _renomear(p),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
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
        decoration: const InputDecoration(hintText: 'Nome do projeto'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancelar')),
        TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('Criar')),
      ],
    ),
  );
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
            const Icon(Icons.lightbulb_outline, size: 56, color: Colors.grey),
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