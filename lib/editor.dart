import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Abre uma folha com campo de texto (multilinha) para editar/criar uma nota.
/// Retorna o texto salvo, ou `null` se cancelado.
Future<String?> editarTexto(BuildContext context,
    {required String titulo, String inicial = ''}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _EditorTexto(titulo: titulo, inicial: inicial),
  );
}

class _EditorTexto extends StatefulWidget {
  const _EditorTexto({required this.titulo, required this.inicial});

  final String titulo;
  final String inicial;

  @override
  State<_EditorTexto> createState() => _EditorTextoState();
}

class _EditorTextoState extends State<_EditorTexto> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.inicial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottom),
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
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(widget.titulo,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              maxLines: null,
              expands: false,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                hintText: 'Escreva sua ideia…',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, capitalizarInicial(_ctrl.text)),
                  child: const Text('Salvar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Copia um texto para a área de transferência e mostra um aviso.
void copiarTexto(BuildContext context, String texto) {
  Clipboard.setData(ClipboardData(text: texto));
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Copiado!')));
}

/// Deixa a PRIMEIRA letra (não-espaço) em maiúscula. Aplicado ao salvar — usar
/// um formatador enquanto digita quebrava a digitação por voz do Android.
String capitalizarInicial(String texto) {
  final m = RegExp(r'\S').firstMatch(texto);
  if (m == null) return texto;
  final i = m.start;
  final letra = texto[i];
  if (letra == letra.toUpperCase()) return texto;
  return texto.replaceRange(i, i + 1, letra.toUpperCase());
}