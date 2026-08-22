import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adm_projetos/caixa3d.dart';
import 'package:adm_projetos/cores.dart';
import 'package:adm_projetos/tema.dart';

AppCores _coresDe(Modo m) => switch (m) {
      Modo.azul => AppCores.azul,
      Modo.escuro => AppCores.escuro,
      Modo.neumB => AppCores.neumB,
      Modo.bege => AppCores.bege,
      Modo.claude => AppCores.claude,
      Modo.onix => AppCores.onix,
    };

void main() {
  test('Modo tem exatamente 6 temas (Azul, Escuro, Dark Game, Bege, Terracota, Ônix)',
      () {
    expect(Modo.values.length, 6);
    expect(
      Modo.values.map((m) => m.rotulo).toList(),
      ['Azul', 'Escuro', 'Dark Game', 'Bege', 'Terracota', 'Ônix'],
    );
  });

  test('Temas antigos migram: claro→Azul, espresso/bege→Bege', () async {
    final nomes = Modo.values.map((m) => m.name).toSet();
    expect(nomes.contains('claro'), isFalse);
    expect(nomes.contains('espresso'), isFalse);
    expect(nomes.contains('begeNeum'), isFalse);
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
