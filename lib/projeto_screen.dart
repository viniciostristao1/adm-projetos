import 'dart:async';

import 'package:flutter/material.dart';

import 'caixa3d.dart';
import 'cores.dart';
import 'editor.dart';
import 'models.dart';
import 'storage.dart';
import 'titulo_destacado.dart';

/// Página de um projeto: caixas de texto (listas numeradas) editáveis do
/// próprio card, com botões de copiar, numerar, editar e excluir.
class ProjetoScreen extends StatefulWidget {
  const ProjetoScreen({super.key, required this.projeto});

  final Projeto projeto;

  @override
  State<ProjetoScreen> createState() => _ProjetoScreenState();
}

class _ProjetoScreenState extends State<ProjetoScreen> {
  final Map<String, GlobalKey<_CaixaNotaState>> _chaves = {};

  Future<void> _salvar() => Storage.instance.salvar();

  GlobalKey<_CaixaNotaState> _chaveDa(String id) =>
      _chaves.putIfAbsent(id, () => GlobalKey<_CaixaNotaState>());

  void _adicionarNota() {
    final nota = Nota(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      texto: '1- ',
    );
    setState(() => widget.projeto.notas.add(nota));
    _salvar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chaveDa(nota.id).currentState?.focarNoFim();
    });
  }

  Future<void> _excluirNota(int i) async {
    setState(() => widget.projeto.notas.removeAt(i));
    await _salvar();
  }

  /// Reordena as caixinhas depois de arrastar.
  void _reordenar(int antigo, int novo) {
    setState(() {
      final n = widget.projeto.notas.removeAt(antigo);
      widget.projeto.notas.insert(novo, n);
    });
    _salvar();
  }

  @override
  Widget build(BuildContext context) {
    final notas = widget.projeto.notas;
    return Scaffold(
      appBar: AppBar(
        title: TituloDestacado(widget.projeto.nome),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _adicionarNota,
        tooltip: 'Nova caixa de texto',
        child: const Icon(Icons.add),
      ),
      body: notas.isEmpty
          ? const _SemNotas()
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              itemCount: notas.length,
              buildDefaultDragHandles: false,
              onReorderItem: _reordenar,
              itemBuilder: (_, i) => Padding(
                key: ValueKey(notas[i].id),
                padding: const EdgeInsets.only(bottom: 10),
                child: _CaixaNota(
                  key: _chaveDa(notas[i].id),
                  nota: notas[i],
                  indice: i,
                  onCopiar: () => copiarTexto(context, notas[i].texto),
                  onExcluir: () => _excluirNota(i),
                ),
              ),
            ),
    );
  }
}

class _CaixaNota extends StatefulWidget {
  const _CaixaNota({
    super.key,
    required this.nota,
    required this.indice,
    required this.onCopiar,
    required this.onExcluir,
  });

  final Nota nota;

  /// Posição da caixinha na lista (para o arrasto).
  final int indice;

  final VoidCallback onCopiar;
  final VoidCallback onExcluir;

  @override
  State<_CaixaNota> createState() => _CaixaNotaState();
}

class _CaixaNotaState extends State<_CaixaNota> {
  late final TextEditingController _ctrl;
  final FocusNode _foco = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.nota.texto);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    Storage.instance.salvar();
    _ctrl.dispose();
    _foco.dispose();
    super.dispose();
  }

  /// Foca a caixinha e leva o cursor para o final do texto (usado ao criar
  /// uma caixinha nova com o botão + e ao tocar na caixinha).
  void focarNoFim() {
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    _foco.requestFocus();
  }

  void _mudou(String novoTexto) {
    widget.nota.texto = novoTexto;
    _debounce?.cancel();
    // Espera 2s de pausa para aplicar a maiúscula pós-"N- " e salvar.
    // Menos que isso cortava a digitação por voz (ela envia o texto em
    // partes com pequenas pausas).
    _debounce = Timer(const Duration(seconds: 2), () {
      final corrigido = maiusculaAposItem(_ctrl.text);
      if (corrigido != _ctrl.text) {
        _ctrl.value = TextEditingValue(
          text: corrigido,
          selection: TextSelection.collapsed(offset: corrigido.length),
        );
        widget.nota.texto = corrigido;
      }
      Storage.instance.salvar();
    });
  }

  /// Limpa TODO o conteúdo da caixinha de uma vez.
  void _limpar() {
    _ctrl.clear();
    _mudou('');
  }

  /// Botão de lista numerada: "enter + próximo número" (fica após o último).
  void _proximoItem() {
    final linha = '${proximoNumeroLista(_ctrl.text)}- ';
    final novo = _ctrl.text.isEmpty || _ctrl.text.endsWith('\n')
        ? _ctrl.text + linha
        : '${_ctrl.text}\n$linha';
    _ctrl.value = TextEditingValue(
      text: novo,
      selection: TextSelection.collapsed(offset: novo.length),
    );
    _foco.requestFocus();
    _mudou(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.luz;
    return Caixa3D(
      cor: app.notaInicio,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ReorderableDragStartListener(
                  index: widget.indice,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 22,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BotaoMini(
                      icone: Icons.format_list_numbered,
                      tooltip: 'Adicionar item da lista',
                      onTap: _proximoItem,
                    ),
                    _BotaoMini(
                      icone: Icons.copy_all_outlined,
                      tooltip: 'Copiar',
                      onTap: widget.onCopiar,
                    ),
                    _BotaoMini(
                      icone: Icons.edit_outlined,
                      tooltip: 'Editar',
                      onTap: _foco.requestFocus,
                    ),
                    _BotaoMini(
                      icone: Icons.cleaning_services,
                      tooltip: 'Limpar conteúdo',
                      onTap: _limpar,
                    ),
                    _BotaoMini(
                      icone: Icons.delete_outline,
                      tooltip: 'Excluir',
                      isDanger: true,
                      onTap: widget.onExcluir,
                    ),
                  ],
                ),
              ],
            ),
          ),
            TextField(
              controller: _ctrl,
              focusNode: _foco,
              minLines: 1,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [LinhasNumeradas()],
              style: TextStyle(
                fontSize: 14.5,
                height: 1.35,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onTap: focarNoFim,
              onChanged: _mudou,
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.fromLTRB(14, 2, 14, 14),
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
  });

  final IconData icone;
  final String tooltip;
  final VoidCallback onTap;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icone,
          size: 20,
          color: isDanger
              ? Colors.red
              : Theme.of(context).colorScheme.onSurfaceVariant),
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
            const Icon(Icons.format_list_numbered, size: 56, color: Colors.grey),
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