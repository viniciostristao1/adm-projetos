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

  testWidgets('busca grifa o termo no texto da caixinha', (tester) async {
    final p = await projetoCom('comprar pão e leite');
    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: p)));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'pão');
    await tester.pump();

    expect(find.byKey(const ValueKey('grifo-busca')), findsOneWidget,
        reason: 'com o termo ativo, o grifo aparece sobre o texto');
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField).first, 'nada disso');
    await tester.pump();
    expect(find.byKey(const ValueKey('grifo-busca')), findsNothing,
        reason: 'sem ocorrência do termo, não há grifo');
  });

  testWidgets('centralizar com seleção vira título e desfazer reverte',
      (tester) async {
    final p = await projetoCom('título do texto\ncorpo do texto');
    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: p)));
    await tester.pump();

    final field = find.byType(TextField).first;
    await tester.tap(field);
    await tester.pump();

    // Seleciona "título do texto" (primeira linha).
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'título do texto\ncorpo do texto',
      selection: TextSelection(baseOffset: 0, extentOffset: 16),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.format_align_center));
    await tester.pump();

    // Virou título centralizado (primeiro campo) e saiu do corpo.
    final titulo = tester.widget<TextField>(find.byType(TextField).first);
    expect(titulo.controller!.text, 'título do texto');
    expect(titulo.textAlign, TextAlign.center);
    final corpo = tester.widget<TextField>(find.byType(TextField).last);
    expect(corpo.controller!.text, 'corpo do texto');
    expect(tester.takeException(), isNull);

    // Desfazer a ação de centralizar devolve tudo.
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    final restaurado = tester.widget<TextField>(find.byType(TextField).first);
    expect(restaurado.controller!.text, 'título do texto\ncorpo do texto');
    expect(tester.takeException(), isNull);
  });

  testWidgets('centralizar sem seleção mostra aviso e não altera nada',
      (tester) async {
    final p = await projetoCom('só um texto');
    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: p)));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.format_align_center));
    await tester.pump();

    expect(
      find.text('Selecione uma palavra ou frase para centralizar'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget); // nenhum título criado
    // Deixa o timer do aviso (4s) expirar para o teste não falhar.
    await tester.pump(const Duration(seconds: 5));
  });
}
