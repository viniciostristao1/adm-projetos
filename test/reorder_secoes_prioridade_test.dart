import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reorder da lista com QUATRO seções por prioridade (V0.1.94):
/// FOCO (cor foco) → EM ANDAMENTO → PRÓXIMOS (cor próximos) → OUTROS, contra o
/// ReorderableListView REAL. Réplica fiel de `_secaoDoProjeto` +
/// `_linhasComSecoes` + `_reordenarComSecoes` de projetos_screen.dart, com
/// foco=amarelo e próximos=verde. Cobre as seções do MEIO (limitadas por
/// cabeçalho dos dois lados), a prioridade do FOCO e a contenção por seção.

const corFoco = 'amarelo';
const corProx = 'verde';

class P {
  final String id;
  final bool andamento;
  final String? cor;
  P(this.id, {this.andamento = false, this.cor});
  @override
  String toString() => id;
}

/// CÓPIA FIEL de `_secaoDoProjeto` (0=FOCO, 1=ANDAMENTO, 2=PRÓXIMOS, 3=OUTROS).
int secaoDe(P p) {
  if (p.cor == corFoco) return 0; // FOCO vence, mesmo se andamento
  if (p.andamento) return 1;
  if (p.cor == corProx) return 2;
  return 3;
}

List<Object> montarLinhas(List<P> projetos) {
  final foco = projetos.where((p) => secaoDe(p) == 0).toList();
  final ativos = projetos.where((p) => secaoDe(p) == 1).toList();
  final prox = projetos.where((p) => secaoDe(p) == 2).toList();
  final outros = projetos.where((p) => secaoDe(p) == 3).toList();
  return <Object>[
    if (foco.isNotEmpty) ...['FOCO · ${foco.length}', ...foco],
    if (ativos.isNotEmpty) ...['EM ANDAMENTO · ${ativos.length}', ...ativos],
    if (prox.isNotEmpty) ...['PRÓXIMOS · ${prox.length}', ...prox],
    if (outros.isNotEmpty) ...['OUTROS · ${outros.length}', ...outros],
  ];
}

class Tela extends StatefulWidget {
  final List<P> inicial;
  const Tela(this.inicial, {super.key});
  @override
  State<Tela> createState() => TelaState();
}

class TelaState extends State<Tela> {
  late List<P> projetos = [...widget.inicial];

  // CÓPIA FIEL de _reordenarComSecoes (V0.1.94) — grupo pela classificação.
  void reordenarComSecoes(int oldIndex, int newIndex) {
    final linhas = montarLinhas(projetos);
    final alvo = linhas[oldIndex];
    if (alvo is! P) return;
    if (newIndex == oldIndex) return;
    var ini = oldIndex;
    while (ini > 0 && linhas[ini - 1] is P) {
      ini--;
    }
    final sec = secaoDe(alvo);
    final grupo = projetos.where((p) => secaoDe(p) == sec).toList();
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
            return SizedBox(
              key: ValueKey(p.id),
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
  await g.moveBy(const Offset(0, 6));
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

/// 2 FOCO (amarelo) + 2 EM ANDAMENTO + 2 PRÓXIMOS (verde) + 1 OUTROS.
List<P> base() => [
      P('F1', cor: corFoco),
      P('F2', cor: corFoco),
      P('A1', andamento: true),
      P('A2', andamento: true),
      P('P1', cor: corProx),
      P('P2', cor: corProx),
      P('O1'),
    ];

void main() {
  test('secaoDe: FOCO vence EM ANDAMENTO (cor de foco + andamento = FOCO)', () {
    expect(secaoDe(P('x', andamento: true, cor: corFoco)), 0);
    expect(secaoDe(P('y', andamento: true, cor: corProx)), 1); // andamento > prox
    expect(secaoDe(P('z', cor: corProx)), 2);
    expect(secaoDe(P('w')), 3);
  });

  test('montarLinhas: ordem FOCO → EM ANDAMENTO → PRÓXIMOS → OUTROS', () {
    final linhas = montarLinhas(base());
    final headers =
        linhas.whereType<String>().map((s) => s.split(' ·').first).toList();
    expect(headers, ['FOCO', 'EM ANDAMENTO', 'PRÓXIMOS', 'OUTROS']);
  });

  testWidgets('FOCO: mover F1 para baixo dentro da seção do topo',
      (tester) async {
    await tester.pumpWidget(Tela(base()));
    final alvo = centroDaLinha(tester, 'F2') + 15;
    await arrastarAte(tester, 'F1', alvo);
    expect(ordem(tester), ['F2', 'F1', 'A1', 'A2', 'P1', 'P2', 'O1']);
  });

  testWidgets('FOCO: F1 não vaza para baixo (fica no fim do FOCO)',
      (tester) async {
    await tester.pumpWidget(Tela(base()));
    final alvo = centroDaLinha(tester, 'O1') + 100;
    await arrastarAte(tester, 'F1', alvo);
    expect(ordem(tester), ['F2', 'F1', 'A1', 'A2', 'P1', 'P2', 'O1']);
  });

  testWidgets('EM ANDAMENTO: mover A1 para baixo dentro da seção',
      (tester) async {
    await tester.pumpWidget(Tela(base()));
    final alvo = centroDaLinha(tester, 'A2') + 15;
    await arrastarAte(tester, 'A1', alvo);
    expect(ordem(tester), ['F1', 'F2', 'A2', 'A1', 'P1', 'P2', 'O1']);
  });

  testWidgets('PRÓXIMOS: P1 não vaza para CIMA (não entra em EM ANDAMENTO)',
      (tester) async {
    await tester.pumpWidget(Tela(base()));
    await arrastarAte(tester, 'P1', 0);
    expect(ordem(tester), ['F1', 'F2', 'A1', 'A2', 'P1', 'P2', 'O1']);
  });

  testWidgets('PRÓXIMOS: P1 não vaza para BAIXO (não cai em OUTROS)',
      (tester) async {
    await tester.pumpWidget(Tela(base()));
    final alvo = centroDaLinha(tester, 'O1') + 100;
    await arrastarAte(tester, 'P1', alvo);
    expect(ordem(tester), ['F1', 'F2', 'A1', 'A2', 'P2', 'P1', 'O1']);
  });

  testWidgets('Sem FOCO nem EM ANDAMENTO: PRÓXIMOS é a 1ª seção',
      (tester) async {
    await tester.pumpWidget(Tela([
      P('P1', cor: corProx),
      P('P2', cor: corProx),
      P('O1'),
    ]));
    final linhas = montarLinhas(
        (tester.state(find.byType(Tela)) as TelaState).projetos);
    expect((linhas.first as String).startsWith('PRÓXIMOS'), isTrue);
  });
}
