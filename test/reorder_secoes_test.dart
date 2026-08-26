import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduz o REORDER da lista de projetos COM SEÇÕES (há projeto em
/// andamento) contra o ReorderableListView REAL do Flutter 3.44.7
/// (`onReorderItem`), arrastando de verdade a alça (6 pontinhos) e conferindo
/// a ordem resultante. Espelha `_reordenarComSecoes` de projetos_screen.dart.

class P {
  final String id;
  final bool andamento;
  P(this.id, this.andamento);
  @override
  String toString() => id;
}

class Tela extends StatefulWidget {
  final List<P> inicial;
  const Tela(this.inicial, {super.key});
  @override
  State<Tela> createState() => TelaState();
}

class TelaState extends State<Tela> {
  late List<P> projetos = [...widget.inicial];

  // CÓPIA FIEL de _reordenarComSecoes (V0.1.69: sem newIndex-- e sem o
  // early-return por [ini,fim] — o dest faz clamp na seção).
  void reordenarComSecoes(int oldIndex, int newIndex) {
    final ativos = projetos.where((p) => p.andamento).toList();
    final outros = projetos.where((p) => !p.andamento).toList();
    final linhas = <Object>[
      'EM ANDAMENTO · ${ativos.length}',
      ...ativos,
      if (outros.isNotEmpty) 'OUTROS · ${outros.length}',
      ...outros,
    ];
    final alvo = linhas[oldIndex];
    if (alvo is! P) return;
    if (newIndex == oldIndex) return;
    var ini = oldIndex;
    while (ini > 0 && linhas[ini - 1] is P) {
      ini--;
    }
    // (SEM early-return por [ini,fim]: o dest abaixo já faz clamp na seção.)
    final grupo = alvo.andamento ? ativos : outros;
    final grupoSem = grupo.where((p) => p.id != alvo.id).toList();
    final dest = (newIndex - ini).clamp(0, grupoSem.length);
    final novoGrupo = [...grupoSem]..insert(dest, alvo);
    setState(() {
      var gi = 0;
      projetos = [
        for (final p in projetos)
          if (grupo.any((g) => g.id == p.id)) novoGrupo[gi++] else p,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final ativos = projetos.where((p) => p.andamento).toList();
    final outros = projetos.where((p) => !p.andamento).toList();
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
    return MaterialApp(
      home: Scaffold(
        body: ReorderableListView.builder(
          itemCount: linhas.length,
          buildDefaultDragHandles: false,
          onReorderItem: reordenarComSecoes,
          itemBuilder: (_, i) {
            final item = linhas[i];
            if (item is String) {
              return SizedBox(
                key: ValueKey('sec-$item'),
                height: 30,
                child: Text(item),
              );
            }
            final p = item as P;
            return Dismissible(
              key: ValueKey(p.id),
              direction: DismissDirection.endToStart,
              child: SizedBox(
                height: 60,
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: Icon(Icons.drag_indicator, key: ValueKey('h-${p.id}')),
                    ),
                    Expanded(child: Text(p.id)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Arrasta a alça da pasta [idAlca] até a posição vertical [alvoY], em passos,
/// deixando o SDK recalcular o gap a cada passo.
Future<void> arrastarAte(WidgetTester tester, String idAlca, double alvoY) async {
  final alca = find.byKey(ValueKey('h-$idAlca'));
  final inicio = tester.getCenter(alca);
  final g = await tester.startGesture(inicio);
  await tester.pump(const Duration(milliseconds: 200));
  await g.moveBy(const Offset(0, 6)); // engaja o ImmediateMultiDrag da alça
  await tester.pump(const Duration(milliseconds: 20));
  final distancia = alvoY - (inicio.dy + 6);
  const passos = 12;
  for (var k = 0; k < passos; k++) {
    await g.moveBy(Offset(0, distancia / passos));
    await tester.pump(const Duration(milliseconds: 30));
  }
  await tester.pump(const Duration(milliseconds: 200));
  await g.up();
  await tester.pumpAndSettle();
}

/// Y do centro da linha da pasta [id] (para mirar o arraste).
double centroDaLinha(WidgetTester tester, String id) =>
    tester.getCenter(find.byKey(ValueKey('h-$id'))).dy;

List<String> ordem(WidgetTester tester) =>
    (tester.state(find.byType(Tela)) as TelaState)
        .projetos
        .map((p) => p.id)
        .toList();

void main() {
  testWidgets('OUTROS: mover C para BAIXO (1 andamento + 3 outros)',
      (tester) async {
    await tester.pumpWidget(Tela([P('A', true), P('C', false), P('D', false), P('E', false)]));
    final alvo = centroDaLinha(tester, 'D') + 15; // 2ª metade de D
    await arrastarAte(tester, 'C', alvo);
    expect(ordem(tester), ['A', 'D', 'C', 'E'],
        reason: 'C deveria descer 1 posição dentro de OUTROS');
  });

  testWidgets('OUTROS: mover E para CIMA (1 andamento + 3 outros)',
      (tester) async {
    await tester.pumpWidget(Tela([P('A', true), P('C', false), P('D', false), P('E', false)]));
    final alvo = centroDaLinha(tester, 'D') - 15; // 1ª metade de D
    await arrastarAte(tester, 'E', alvo);
    expect(ordem(tester), ['A', 'C', 'E', 'D'],
        reason: 'E deveria subir 1 posição dentro de OUTROS');
  });

  testWidgets('OUTROS: C não cruza para cima do projeto em andamento',
      (tester) async {
    await tester.pumpWidget(Tela([P('A', true), P('C', false), P('D', false), P('E', false)]));
    await arrastarAte(tester, 'C', 0); // tenta subir para o topo (cross-section)
    expect(ordem(tester), ['A', 'C', 'D', 'E'],
        reason: 'move cross-section deve ser no-op (restrição da seção)');
  });

  testWidgets('2 andamento: mover A para BAIXO dentro de EM ANDAMENTO',
      (tester) async {
    await tester.pumpWidget(Tela([P('A', true), P('B', true), P('C', false)]));
    final alvo = centroDaLinha(tester, 'B') + 15; // 2ª metade de B
    await arrastarAte(tester, 'A', alvo);
    expect(ordem(tester), ['B', 'A', 'C'],
        reason: 'A deveria descer abaixo de B na seção EM ANDAMENTO');
  });

  testWidgets('2 andamento: mover B para CIMA dentro de EM ANDAMENTO',
      (tester) async {
    await tester.pumpWidget(Tela([P('A', true), P('B', true), P('C', false)]));
    final alvo = centroDaLinha(tester, 'A') - 15; // 1ª metade de A
    await arrastarAte(tester, 'B', alvo);
    expect(ordem(tester), ['B', 'A', 'C'],
        reason: 'B deveria subir acima de A na seção EM ANDAMENTO');
  });

  testWidgets('3 andamento: mover A para o FIM da seção EM ANDAMENTO',
      (tester) async {
    await tester.pumpWidget(
        Tela([P('A', true), P('B', true), P('C', true), P('D', false)]));
    final alvo = centroDaLinha(tester, 'C') + 15; // 2ª metade de C
    await arrastarAte(tester, 'A', alvo);
    expect(ordem(tester), ['B', 'C', 'A', 'D'],
        reason: 'A vai para o fim de EM ANDAMENTO, sem cair em OUTROS');
  });

  testWidgets('3 andamento: mover C para o TOPO da seção EM ANDAMENTO',
      (tester) async {
    await tester.pumpWidget(
        Tela([P('A', true), P('B', true), P('C', true), P('D', false)]));
    final alvo = centroDaLinha(tester, 'A') - 15; // 1ª metade de A
    await arrastarAte(tester, 'C', alvo);
    expect(ordem(tester), ['C', 'A', 'B', 'D'],
        reason: 'C sobe para o topo de EM ANDAMENTO');
  });
}
