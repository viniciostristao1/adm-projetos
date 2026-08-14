import 'dart:convert';
import 'dart:io';

import 'package:adm_projetos/models.dart';
import 'package:adm_projetos/projeto_screen.dart';
import 'package:adm_projetos/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testes de regressão do bug "escrever e sair rápido da tela perde o texto".
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

  Future<String> textoSalvo() async {
    final json = jsonDecode(await Storage.instance.exportarJson()) as List;
    return json[0]['tarefas'][0]['texto'] as String;
  }

  testWidgets('texto digitado sobrevive a saida imediata da tela',
      (tester) async {
    final p = Projeto(
      id: 'p1',
      nome: 'Projeto A',
      tarefas: [Nota(id: 'n1', texto: '')],
    );
    await Storage.instance.carregar();
    await Storage.instance.substituir([p]);

    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: p)));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'minha ideia');
    await tester.pump();

    // Sai imediatamente, sem esperar timers nem commits do teclado.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(await textoSalvo(), 'minha ideia');
  });

  testWidgets('texto em composicao do IME sobrevive a saida imediata',
      (tester) async {
    final p = Projeto(
      id: 'p1',
      nome: 'Projeto A',
      tarefas: [Nota(id: 'n1', texto: '')],
    );
    await Storage.instance.carregar();
    await Storage.instance.substituir([p]);

    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: p)));
    await tester.pump();

    final field = find.byType(TextField).first;
    await tester.tap(field);
    await tester.pump();
    // Digitação real com a última palavra ainda em composição (GBoard).
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'minha ide',
      composing: TextRange(start: 6, end: 9),
    ));
    await tester.pump();

    // Sai imediatamente (o IME não chega a confirmar a composição).
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(await textoSalvo(), 'minha ide');
  });

  testWidgets('dispose derrama o texto do controlador para o modelo',
      (tester) async {
    final p = Projeto(
      id: 'p1',
      nome: 'Projeto A',
      tarefas: [Nota(id: 'n1', texto: '')],
    );
    await Storage.instance.carregar();
    await Storage.instance.substituir([p]);

    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: p)));
    await tester.pump();

    // Texto que chegou ao controlador mas ainda não passou por onChanged
    // (caso-limite do teclado ao fechar a tela no meio de uma palavra).
    final tf = tester.widget<TextField>(find.byType(TextField).first);
    tf.controller!.text = 'texto do controlador';

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(await textoSalvo(), 'texto do controlador');
  });
}
