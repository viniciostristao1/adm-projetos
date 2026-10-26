import 'dart:io';

import 'package:adm_projetos/models.dart';
import 'package:adm_projetos/projeto_screen.dart';
import 'package:adm_projetos/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Voltar dentro de um projeto aberto "em modo pastas" (ex.: Estudos):
/// o 1º voltar retorna À GRADE de pastas; só o 2º sai para a lista.
/// Sem `modoPastasInicial`, o voltar sai direto (comportamento antigo).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('adm_voltar_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return dir.path;
      return null;
    });
  });

  Future<void> abrirProjeto(WidgetTester tester, Projeto projeto,
      {bool modoPastas = false}) async {
    await Storage.instance.carregar();
    await Storage.instance.substituir([projeto]);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (ctx) => Scaffold(
                body: Center(
                    child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                      builder: (_) => ProjetoScreen(
                          projeto: projeto,
                          modoPastasInicial: modoPastas))),
                  child: const Text('ABRIR'),
                )),
              )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ABRIR'));
    await tester.pumpAndSettle();
  }

  testWidgets('1º voltar dentro da pasta volta à grade; 2º sai',
      (tester) async {
    final projeto = Projeto(
        id: 'p1', nome: 'Estudos', tarefas: [Nota(id: 'n1', texto: 'a')]);
    await abrirProjeto(tester, projeto, modoPastas: true);

    // Grade de pastas (modo pastas inicial).
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(TabBarView), findsNothing);

    // Entra na pasta (vira abas, na mesma rota).
    await tester.tap(find.text('Tarefas'));
    await tester.pumpAndSettle();
    expect(find.byType(TabBarView), findsOneWidget);

    // 1º voltar do sistema → grade (não sai da rota).
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(TabBarView), findsNothing);
    expect(find.text('Estudos'), findsWidgets);

    // 2º voltar → sai para a lista.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('ABRIR'), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
  });

  testWidgets('sem modoPastasInicial o voltar sai direto', (tester) async {
    final projeto = Projeto(
        id: 'p1', nome: 'P', tarefas: [Nota(id: 'n1', texto: 'a')]);
    await abrirProjeto(tester, projeto);

    expect(find.byType(TabBarView), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('ABRIR'), findsOneWidget);
  });
}
