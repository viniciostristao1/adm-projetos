import 'dart:io';

import 'package:adm_projetos/models.dart';
import 'package:adm_projetos/projeto_screen.dart';
import 'package:adm_projetos/projetos_screen.dart';
import 'package:adm_projetos/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regressões das melhorias V0.1.42:
/// - to-do/numeração respeitam a linha do cursor (mesmo vazia) — bug #2;
/// - lupa global acha conteúdo em Tarefas/Ideias e abre a caixinha — item #6.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('adm_teste_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return dir.path;
      return null;
    });
  });

  testWidgets('to-do criado numa 2ª linha vazia fica na 2ª linha (bug #2)',
      (tester) async {
    // Linha 1 com conteúdo, linha 2 vazia (o usuário deu Enter e não digitou).
    final p = Projeto(
      id: 'p1',
      nome: 'P',
      tarefas: [Nota(id: 'n1', texto: 'primeira linha\n')],
    );
    await Storage.instance.carregar();
    await Storage.instance.substituir([p]);

    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: p)));
    await tester.pump();

    final field = find.byType(TextField).first;
    await tester.tap(field);
    await tester.pump();
    // Cursor na SEGUNDA linha (vazia), no fim do texto (offset 15).
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'primeira linha\n',
      selection: TextSelection.collapsed(offset: 15),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pump();

    final tf = tester.widget<TextField>(field);
    final linhas = tf.controller!.text.split('\n');
    expect(linhas[0], 'primeira linha',
        reason: 'a 1ª linha não pode ser tocada');
    expect(linhas.length, 2);
    expect(linhas[1].startsWith('☐'), isTrue,
        reason: 'o to-do nasce na 2ª linha, onde está o cursor');
    expect(tester.takeException(), isNull);
  });

  testWidgets('lupa global acha palavra em Ideias e abre a caixinha (#6)',
      (tester) async {
    final p = Projeto(
      id: 'p1',
      nome: 'Compras',
      tarefas: [Nota(id: 'n1', texto: 'nada aqui')],
      futuro: [Nota(id: 'n2', texto: 'comprar guardanapo azul')],
    );
    await Storage.instance.carregar();
    await Storage.instance.substituir([p]);

    await tester.pumpWidget(const MaterialApp(home: ProjetosScreen()));
    await tester.pumpAndSettle();

    // Abre a lupa e busca uma palavra que só existe em Ideias.
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'guardanapo');
    await tester.pump();

    // Aparece o resultado de conteúdo (projeto · aba).
    expect(find.text('Compras · Ideias'), findsOneWidget);

    // Tocar no resultado abre o projeto direto na caixinha encontrada.
    await tester.tap(find.text('Compras · Ideias'));
    await tester.pumpAndSettle();

    expect(find.byType(ProjetoScreen), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) =>
          w is TextField && w.controller?.text == 'comprar guardanapo azul'),
      findsOneWidget,
      reason: 'abriu na aba Ideias, mostrando a caixinha achada',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('esconder o teclado solta o foco da caixinha (bug #1)',
      (tester) async {
    addTearDown(tester.view.resetViewInsets);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    final p = Projeto(
      id: 'p1',
      nome: 'P',
      tarefas: [Nota(id: 'n1', texto: 'oi')],
    );
    await Storage.instance.carregar();
    await Storage.instance.substituir([p]);

    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: p)));
    await tester.pump();

    final field = find.byType(TextField).first;
    await tester.tap(field);
    await tester.pump();
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

    // Teclado ABRE (viewInsets.bottom > 0).
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    // Teclado FECHA (setinha para baixo): bottom → 0. O foco é solto
    // IMEDIATAMENTE (V0.1.63) — sem debounce, senão o teclado voltava a subir.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'didChangeMetrics não pode lançar');
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse,
        reason: 'ao esconder o teclado, o foco é solto (não volta sozinho)');
  });

  testWidgets('teclado NÃO fecha durante composição IME (troca de layout)',
      (tester) async {
    addTearDown(tester.view.resetViewInsets);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    final p = Projeto(
      id: 'p1',
      nome: 'P',
      tarefas: [Nota(id: 'n1', texto: 'oi')],
    );
    await Storage.instance.carregar();
    await Storage.instance.substituir([p]);

    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: p)));
    await tester.pump();

    final field = find.byType(TextField).first;
    await tester.tap(field);
    await tester.pump();
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

    // Teclado ABRE.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    // Simula o usuário NO MEIO de uma palavra (IME compondo).
    final ctrl =
        tester.widget<EditableText>(find.byType(EditableText).first).controller;
    ctrl.value = const TextEditingValue(
      text: 'palavra',
      selection: TextSelection.collapsed(offset: 7),
      composing: TextRange(start: 0, end: 7),
    );
    await tester.pump();

    // "Altura 0" passageiro (troca de layout do teclado) COM composição ativa:
    // não pode soltar o foco (senão fecharia no meio da digitação).
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();

    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue,
        reason: 'compondo (meio da palavra) → não solta o foco');
  });

  testWidgets('lupa global também acha projeto por nome (#6)', (tester) async {
    final p = Projeto(id: 'p1', nome: 'Viagem Chile', tarefas: []);
    await Storage.instance.carregar();
    await Storage.instance.substituir([p]);

    await tester.pumpWidget(const MaterialApp(home: ProjetosScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'chile');
    await tester.pump();

    expect(find.text('PROJETOS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
