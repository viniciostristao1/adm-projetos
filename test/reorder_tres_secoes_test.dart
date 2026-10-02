import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reorder da lista de projetos com TRÊS seções (EM ANDAMENTO / EM ABERTO por
/// cor / OUTROS), contra o ReorderableListView REAL do Flutter 3.44.7
/// (`onReorderItem`). A seção do MEIO (EM ABERTO) é limitada por cabeçalho dos
/// DOIS lados — o caso mais arriscado para o `ini` (recuo até a borda) e o
/// `dest` (clamp dentro da seção). Espelha `_reordenarComSecoes` +
/// `_linhasComSecoes` + `_grupoDoProjeto` de projetos_screen.dart (V0.1.92),
/// com a "cor em aberto" fixada em 'verde'.

const corAberto = 'verde';

class P {
  final String id;
  final bool andamento;
  final String? cor;
  P(this.id, {this.andamento = false, this.cor});
  @override
  String toString() => id;
}

/// CÓPIA FIEL de `_linhasComSecoes` (corAberto = 'verde').
List<Object> montarLinhas(List<P> projetos) {
  final ativos = projetos.where((p) => p.andamento).toList();
  final aberto =
      projetos.where((p) => !p.andamento && p.cor == corAberto).toList();
  final outros =
      projetos.where((p) => !p.andamento && p.cor != corAberto).toList();
  return <Object>[
    if (ativos.isNotEmpty) ...['EM ANDAMENTO · ${ativos.length}', ...ativos],
    if (aberto.isNotEmpty) ...['EM ABERTO · ${aberto.length}', ...aberto],
    if (outros.isNotEmpty) ...['OUTROS · ${outros.length}', ...outros],
  ];
}

/// CÓPIA FIEL de `_grupoDoProjeto`.
List<P> grupoDe(List<P> projetos, P alvo) {
  if (alvo.andamento) return projetos.where((p) => p.andamento).toList();
  if (alvo.cor == corAberto) {
    return projetos.where((p) => !p.andamento && p.cor == corAberto).toList();
  }
  return projetos.where((p) => !p.andamento && p.cor != corAberto).toList();
}

class Tela extends StatefulWidget {
  final List<P> inicial;
  const Tela(this.inicial, {super.key});
  @override
  State<Tela> createState() => TelaState();
}

class TelaState extends State<Tela> {
  late List<P> projetos = [...widget.inicial];

  // CÓPIA FIEL de _reordenarComSecoes (V0.1.92, 3 seções).
  void reordenarComSecoes(int oldIndex, int newIndex) {
    final linhas = montarLinhas(projetos);
    final alvo = linhas[oldIndex];
    if (alvo is! P) return;
    if (newIndex == oldIndex) return;
    var ini = oldIndex;
    while (ini > 0 && linhas[ini - 1] is P) {
      ini--;
    }
    final grupo = grupoDe(projetos, alvo);
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
    final linhas = montarLinhas(projetos);
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
                      child:
                          Icon(Icons.drag_indicator, key: ValueKey('h-${p.id}')),
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

double centroDaLinha(WidgetTester tester, String id) =>
    tester.getCenter(find.byKey(ValueKey('h-$id'))).dy;

List<String> ordem(WidgetTester tester) =>
    (tester.state(find.byType(Tela)) as TelaState)
        .projetos
        .map((p) => p.id)
        .toList();

/// Cenário base: 1 em andamento (A), 3 verdes/EM ABERTO (V1,V2,V3) e 2
/// OUTROS (O1,O2).
List<P> base() => [
      P('A', andamento: true),
      P('V1', cor: corAberto),
      P('V2', cor: corAberto),
      P('V3', cor: corAberto),
      P('O1'),
      P('O2'),
    ];

void main() {
  testWidgets('EM ABERTO: mover V1 para BAIXO (dentro da seção do meio)',
      (tester) async {
    await tester.pumpWidget(Tela(base()));
    final alvo = centroDaLinha(tester, 'V2') + 15; // 2ª metade de V2
    await arrastarAte(tester, 'V1', alvo);
    expect(ordem(tester), ['A', 'V2', 'V1', 'V3', 'O1', 'O2'],
        reason: 'V1 desce 1 dentro de EM ABERTO');
  });

  testWidgets('EM ABERTO: mover V3 para CIMA (dentro da seção do meio)',
      (tester) async {
    await tester.pumpWidget(Tela(base()));
    final alvo = centroDaLinha(tester, 'V2') - 15; // 1ª metade de V2
    await arrastarAte(tester, 'V3', alvo);
    expect(ordem(tester), ['A', 'V1', 'V3', 'V2', 'O1', 'O2'],
        reason: 'V3 sobe 1 dentro de EM ABERTO');
  });

  testWidgets('EM ABERTO: V1 não vaza para CIMA (não entra em EM ANDAMENTO)',
      (tester) async {
    await tester.pumpWidget(Tela(base()));
    await arrastarAte(tester, 'V1', 0); // tenta ir para o topo absoluto
    expect(ordem(tester), ['A', 'V1', 'V2', 'V3', 'O1', 'O2'],
        reason: 'cross-section para cima deve grudar no topo de EM ABERTO (no-op)');
  });

  testWidgets('EM ABERTO: V1 não vaza para BAIXO (não cai em OUTROS)',
      (tester) async {
    await tester.pumpWidget(Tela(base()));
    final alvo = centroDaLinha(tester, 'O2') + 100; // bem abaixo, em OUTROS
    await arrastarAte(tester, 'V1', alvo);
    expect(ordem(tester), ['A', 'V2', 'V3', 'V1', 'O1', 'O2'],
        reason: 'V1 gruda no FIM de EM ABERTO, sem entrar em OUTROS');
  });

  testWidgets('OUTROS (abaixo de EM ABERTO) ainda reordena',
      (tester) async {
    await tester.pumpWidget(Tela(base()));
    final alvo = centroDaLinha(tester, 'O2') + 15; // 2ª metade de O2
    await arrastarAte(tester, 'O1', alvo);
    expect(ordem(tester), ['A', 'V1', 'V2', 'V3', 'O2', 'O1'],
        reason: 'O1 desce dentro de OUTROS');
  });

  testWidgets('EM ANDAMENTO (acima de EM ABERTO) não vaza para baixo',
      (tester) async {
    await tester.pumpWidget(Tela([
      P('A', andamento: true),
      P('B', andamento: true),
      P('V1', cor: corAberto),
      P('O1'),
    ]));
    final alvo = centroDaLinha(tester, 'O1') + 50; // tenta descer tudo
    await arrastarAte(tester, 'A', alvo);
    expect(ordem(tester), ['B', 'A', 'V1', 'O1'],
        reason: 'A gruda no fim de EM ANDAMENTO, sem cair em EM ABERTO/OUTROS');
  });
}
