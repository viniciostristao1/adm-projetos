import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adm_projetos/caixa3d.dart';
import 'package:adm_projetos/cores.dart';
import 'package:adm_projetos/tema.dart';

AppCores _coresDe(Modo m) => switch (m) {
      Modo.azul => AppCores.azul,
      Modo.escuro => AppCores.escuro,
      Modo.neumB => AppCores.neumB,
      Modo.claude => AppCores.claude,
      Modo.onix => AppCores.onix,
      Modo.creme => AppCores.creme,
      Modo.papel => AppCores.papel,
    };

void main() {
  test('Modo tem exatamente 7 temas (Azul, Escuro, Dark Game, Terracota, Ônix, Creme, Papel)',
      () {
    expect(Modo.values.length, 7);
    expect(
      Modo.values.map((m) => m.rotulo).toList(),
      ['Azul', 'Escuro', 'Dark Game', 'Terracota', 'Ônix', 'Creme', 'Papel'],
    );
  });

  test('Temas antigos migram: claro/espresso/bege/begeNeum/luz→Azul', () async {
    final nomes = Modo.values.map((m) => m.name).toSet();
    expect(nomes.contains('claro'), isFalse);
    expect(nomes.contains('espresso'), isFalse);
    expect(nomes.contains('begeNeum'), isFalse);
    expect(nomes.contains('bege'), isFalse);
    expect(nomes.contains('luz'), isFalse);
  });

  test('Densidade tem Confortável e Compacto', () {
    expect(
      Densidade.values.map((d) => d.rotulo).toList(),
      ['Confortável', 'Compacto'],
    );
  });

  for (final m in Modo.values) {
    testWidgets('tema ${m.rotulo} constrói as superfícies sem erro',
        (tester) async {
      final app = _coresDe(m);
      await tester.pumpWidget(MaterialApp(
        themeMode: ThemeMode.dark,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.dark(),
          extensions: [app],
        ),
        home: Scaffold(
          body: Fundo(
            child: Column(
              children: [
                Caixa3D(cor: app.notaInicio, child: const Text('caixa')),
                BotaoNeum(
                  onTap: () {},
                  child: const Icon(Icons.add),
                ),
                TextField(
                  style: TextStyle(
                    fontFamilyFallback: const ['NotoSansSymbols2'],
                    color: app.textoUI,
                  ),
                  decoration: const InputDecoration(hintText: 'hint'),
                ),
              ],
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  }
}
