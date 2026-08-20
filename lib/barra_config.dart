import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Identifica cada botão da barra de ferramentas da caixinha. A ORDEM em que
/// os botões aparecem na barra é configurável pelo usuário (Configurações →
/// "Ordem dos botões da barra") e guardada por [BarraController].
///
/// ⚠️ Ao adicionar uma ferramenta nova, inclua-a aqui, dê um [rotulo] e um
/// [icone] na extensão abaixo, e trate-a no `_botaoFerramenta` do
/// `projeto_screen.dart`. Ferramentas novas entram automaticamente no FIM da
/// ordem salva de quem já usava o app (ver [BarraController.carregar]).
enum Ferramenta {
  copiar,
  desfazer,
  feito,
  numerar, // só aparece na aba Tarefas
  todo,
  mover,
  extremo,
  link,
  imagem,
  comentario,
  editar,
  centralizar,
  limpar,
  excluir,
}

extension FerramentaInfo on Ferramenta {
  /// Nome amigável mostrado na tela de reordenar.
  String get rotulo => switch (this) {
        Ferramenta.copiar => 'Copiar',
        Ferramenta.desfazer => 'Desfazer',
        Ferramenta.feito => 'Marcar como feito',
        Ferramenta.numerar => 'Numerar linha (só Tarefas)',
        Ferramenta.todo => 'Item de to-do (☐)',
        Ferramenta.mover => 'Mover de aba',
        Ferramenta.extremo => 'Ir ao topo / pé',
        Ferramenta.link => 'Link',
        Ferramenta.imagem => 'Ler imagem (OCR)',
        Ferramenta.comentario => 'Comentário',
        Ferramenta.editar => 'Editar (focar no fim)',
        Ferramenta.centralizar => 'Centralizar linha',
        Ferramenta.limpar => 'Limpar conteúdo',
        Ferramenta.excluir => 'Excluir',
      };

  /// Ícone REPRESENTATIVO (na barra alguns alternam conforme o estado).
  IconData get icone => switch (this) {
        Ferramenta.copiar => Icons.copy_all_outlined,
        Ferramenta.desfazer => Icons.undo,
        Ferramenta.feito => Icons.check_box_outline_blank,
        Ferramenta.numerar => Icons.format_list_numbered,
        Ferramenta.todo => Icons.checklist,
        Ferramenta.mover => Icons.swap_vert,
        Ferramenta.extremo => Icons.unfold_more,
        Ferramenta.link => Icons.add_link,
        Ferramenta.imagem => Icons.image_outlined,
        Ferramenta.comentario => Icons.chat_bubble_outline,
        Ferramenta.editar => Icons.edit_outlined,
        Ferramenta.centralizar => Icons.format_align_center,
        Ferramenta.limpar => Icons.cleaning_services,
        Ferramenta.excluir => Icons.delete_outline,
      };
}

/// Guarda a ORDEM dos botões da barra de ferramentas (a mesma para todas as
/// caixinhas), persistida em SharedPreferences. Notifica ao mudar para as
/// barras se reconstruírem.
class BarraController extends ChangeNotifier {
  static const _chave = 'barra_ordem_v1';

  List<Ferramenta> _ordem = List.of(Ferramenta.values);

  /// Ordem atual dos botões (esquerda → direita, após o pino de arrastar).
  List<Ferramenta> get ordem => List.unmodifiable(_ordem);

  /// Carrega a ordem salva (chamar no início do app). Ferramentas que ainda
  /// não estavam na ordem salva (ex.: adicionadas numa atualização) entram no
  /// FIM, e nomes desconhecidos são ignorados.
  Future<void> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final salvo = prefs.getStringList(_chave);
    if (salvo != null) {
      final porNome = {for (final f in Ferramenta.values) f.name: f};
      final lista = <Ferramenta>[];
      for (final nome in salvo) {
        final f = porNome[nome];
        if (f != null && !lista.contains(f)) lista.add(f);
      }
      for (final f in Ferramenta.values) {
        if (!lista.contains(f)) lista.add(f);
      }
      _ordem = lista;
    }
    notifyListeners();
  }

  Future<void> definirOrdem(List<Ferramenta> nova) async {
    _ordem = List.of(nova);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_chave, nova.map((e) => e.name).toList());
  }

  /// Volta para a ordem padrão de fábrica.
  Future<void> restaurar() => definirOrdem(List.of(Ferramenta.values));
}

/// Instância única usada pelo app.
final BarraController barraController = BarraController();

/// Tela para reordenar (arrastar) os botões da barra de ferramentas das
/// caixinhas. Cada mudança é salva na hora via [barraController].
class OrdemBarraScreen extends StatefulWidget {
  const OrdemBarraScreen({super.key});

  @override
  State<OrdemBarraScreen> createState() => _OrdemBarraScreenState();
}

class _OrdemBarraScreenState extends State<OrdemBarraScreen> {
  late List<Ferramenta> _ordem;

  @override
  void initState() {
    super.initState();
    _ordem = List.of(barraController.ordem);
  }

  void _reordenar(int antigo, int novo) {
    // onReorderItem já entrega o novo índice ajustado (como nas outras listas
    // do app): basta remover e inserir, sem o "-1" do onReorder antigo.
    setState(() {
      final f = _ordem.removeAt(antigo);
      _ordem.insert(novo, f);
    });
    barraController.definirOrdem(_ordem);
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ordem dos botões'),
        actions: [
          TextButton(
            onPressed: () {
              barraController.restaurar();
              setState(() => _ordem = List.of(barraController.ordem));
            },
            child: const Text('Restaurar'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Arraste para mudar a ordem dos botões na barra de todas as '
              'caixinhas. O primeiro da lista fica logo após o pino de '
              'arrastar.',
              style: TextStyle(color: s.onSurfaceVariant, fontSize: 13),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: _ordem.length,
              onReorderItem: _reordenar,
              itemBuilder: (context, i) {
                final f = _ordem[i];
                return Card(
                  key: ValueKey(f),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: Icon(f.icone,
                        color: f == Ferramenta.excluir
                            ? Colors.redAccent
                            : s.onSurface),
                    title: Text(f.rotulo),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: Icon(Icons.drag_handle,
                          color: s.onSurfaceVariant),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
