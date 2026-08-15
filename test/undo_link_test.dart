import 'dart:io';

import 'package:adm_projetos/models.dart';
import 'package:adm_projetos/projeto_screen.dart';
import 'package:adm_projetos/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regressões: desfazer apagar (botão na barra) e diálogo de links
/// (era tela branca — lista de tamanho fixo recebendo add()).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('adm_teste_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(
            'plugins.flutter.io/path_provider'), (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return dir.path;
      }
      return null;
    });
  });

  Future<Projeto> projetoCom(String texto) async {
    final p = Projeto(
      id: 'p1',
      nome: 'Projeto A',
      tarefas: [Nota(id: 'n1', texto: texto)],
    );
    await Storage.instance.carregar();
    await Storage.instance.substituir([p]);
    return p;
  }

  testWidgets('desfazer restaura a palavra digitada e apagada',
      (tester) async {
    final p = await projetoCom('');
    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: p)));
    await tester.pump();

    final field = find.byType(TextField).first;
    await tester.tap(field);
    await tester.pump();

    // Digitação realista do GBoard (palavra em composição) e apagamento.
    tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'palavra', composing: TextRange(start: 0, end: 7)));
    await tester.pump();
    tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: ''));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();

    final tf = tester.widget<TextField>(field);
    expect(tf.controller!.text, 'palavra');
    expect(tester.takeException(), isNull);
  });

  testWidgets('desfazer restaura a rajada inteira de apagamentos',
      (tester) async {
    final p = await projetoCom('');
    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: p)));
    await tester.pump();

    final field = find.byType(TextField).first;
    await tester.tap(field);
    await tester.pump();
    tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: 'uma frase bem escrita'));
    await tester.pump();
    tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: 'uma'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();

    final tf = tester.widget<TextField>(field);
    expect(tf.controller!.text, 'uma frase bem escrita');
    expect(tester.takeException(), isNull);
  });

  testWidgets('clicar no ícone de link abre o diálogo (sem tela branca)',
      (tester) async {
    final p = await projetoCom('com link');
    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: p)));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add_link));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'abrir o diálogo de links não pode lançar exceção');
    expect(find.text('Links'), findsOneWidget);
  });

  testWidgets('diálogo de link aceita digitar URL e salvar sem crash',
      (tester) async {
    final p = await projetoCom('');
    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: p)));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add_link));
    await tester.pumpAndSettle();
    expect(find.text('Links'), findsOneWidget);

    final urlField = find.byType(TextField).last;
    await tester.enterText(
        urlField, 'https://www.youtube.com/watch?v=abc');
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'digitar no campo de URL não pode crashar');

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
