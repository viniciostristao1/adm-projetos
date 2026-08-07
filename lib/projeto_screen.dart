import 'package:flutter/material.dart';

import 'editor.dart';
import 'models.dart';
import 'storage.dart';

/// Página de um projeto: as caixas de texto, com botões de copiar e editar.
class ProjetoScreen extends StatefulWidget {
  const ProjetoScreen({super.key, required this.projeto});

  final Projeto projeto;

  @override
  State<ProjetoScreen> createState() => _ProjetoScreenState();
}

class _ProjetoScreenState extends State<ProjetoScreen> {
  Future<void> _salvar() => Storage.instance.salvar();

  Future<void> _adicionarNota() async {
    final texto = await editarTexto(context, titulo: 'Nova caixa de texto');
    if (texto == null) return;
    if (texto.trim().isEmpty) return;
    setState(() {
      widget.projeto.notas.add(Nota(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        texto: texto,
      ));
    });
    await _salvar();
  }

  Future<void> _editarNota(int i) async {
    final nota = widget.projeto.notas[i];
    final texto = await editarTexto(context,
        titulo: 'Editar caixa', inicial: nota.texto);
    if (texto == null) return;
    setState(() => nota.texto = texto);
    await _salvar();
  }

  Future<void> _excluirNota(int i) async {
    setState(() => widget.projeto.notas.removeAt(i));
    await _salvar();
  }

  @override
  Widget build(BuildContext context) {
    final notas = widget.projeto.notas;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projeto.nome),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _adicionarNota,
        tooltip: 'Nova caixa de texto',
        child: const Icon(Icons.add),
      ),
      body: notas.isEmpty
          ? const _SemNotas()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              itemCount: notas.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _NotaCard(
                texto: notas[i].texto,
                onCopiar: () => copiarTexto(context, notas[i].texto),
                onEditar: () => _editarNota(i),
                onExcluir: () => _excluirNota(i),
              ),
            ),
    );
  }
}

class _NotaCard extends StatelessWidget {
  const _NotaCard({
    required this.texto,
    required this.onCopiar,
    required this.onEditar,
    required this.onExcluir,
  });

  final String texto;
  final VoidCallback onCopiar;
  final VoidCallback onEditar;
  final VoidCallback onExcluir;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              texto,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14.5, height: 1.35),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _BotaoMini(
                  icone: Icons.copy_all_outlined,
                  tooltip: 'Copiar',
                  onTap: onCopiar,
                ),
                _BotaoMini(
                  icone: Icons.edit_outlined,
                  tooltip: 'Editar',
                  onTap: onEditar,
                ),
                _BotaoMini(
                  icone: Icons.delete_outline,
                  tooltip: 'Excluir',
                  isDanger: true,
                  onTap: onExcluir,
                ),
              ],
            ),
          ],
        ),
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
          size: 20, color: isDanger ? Colors.red : Colors.grey.shade600),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}

class _SemNotas extends StatelessWidget {
  const _SemNotas();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notes, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Nenhuma caixa ainda',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
}