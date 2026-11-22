import 'dart:io';

import 'package:adm_projetos/models.dart';
import 'package:adm_projetos/projeto_screen.dart';
import 'package:adm_projetos/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Testes do botão "•••" (Ferramenta.minimizar): minimiza a caixinha para as
/// 3 primeiras linhas do texto, com reticências na 3ª; o estado fica salvo no
/// modelo (`Nota.minimizada`) e é lembrado ao fechar/reabrir o app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('adm_minimizar_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return dir.path;
      return null;
    });
  });

  group('Nota.minimizada (serialização)', () {
    test('round-trip preserva o estado minimizada', () {
      final n = Nota(id: '1', texto: 'a', minimizada: true);
      expect(Nota.fromJson(n.toJson()).minimizada, isTrue);
    });

    test('JSON antigo sem o campo vira false (backward-compatible)', () {
      final n = Nota.fromJson({'id': '1', 'texto': 'a'});
      expect(n.minimizada, isFalse);
    });

    test('toJson omite minimizada quando false (JSON antigo fica igual)', () {
      final n = Nota(id: '1', texto: 'a');
      expect(n.toJson().containsKey('minimizada'), isFalse);
    });
  });

  // NOVO LAYOUT (V0.1.237): "minimizar" (•••) saiu do topo de cada card e
  // virou uma ferramenta da BARRA ÚNICA acima do teclado — só aparece com a
  // caixinha FOCADA. Para minimizar, foca-se a caixinha e toca-se no "•••" da
  // barra; a prévia minimizada traz o "•••" (expandir) e o DOCK (arrastar/
  // copiar/seleção) continua visível mesmo minimizada.
  Future<void> minimizarPelaBarra(WidgetTester tester) async {
    // Foca a caixinha → a barra única (com o "•••") aparece acima do teclado.
    // (Enquanto focada, usa-se pump() — pumpAndSettle travaria no cursor
    // piscante.) A barra rola na horizontal; revela o "•••" e toca.
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.dragUntilVisible(
      find.byIcon(Icons.more_horiz),
      find.byType(SingleChildScrollView).last,
      const Offset(-120, 0),
    );
    await tester.tap(find.byIcon(Icons.more_horiz));
    // O minimizar desfoca a caixinha → pumpAndSettle volta a ser seguro.
    await tester.pumpAndSettle();
  }

  testWidgets('••• (barra) minimiza (3 linhas) e a prévia expande',
      (tester) async {
    await Storage.instance.carregar();
    final nota = Nota(
      id: 'n1',
      texto: List.generate(12, (i) => 'linha ${i + 1}').join('\n'),
    );
    final projeto = Projeto(id: 'p1', nome: 'P', tarefas: [nota]);
    await Storage.instance.substituir([projeto]);

    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: projeto)));
    await tester.pumpAndSettle();

    // Expandida: o campo de texto normal está montado.
    expect(find.byType(TextField), findsOneWidget);
    expect(nota.minimizada, isFalse);

    await minimizarPelaBarra(tester);

    // Minimizada: o campo some e aparece a prévia de 3 linhas com reticências.
    expect(find.byType(TextField), findsNothing);
    final previa = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.maxLines == 3 && t.overflow == TextOverflow.ellipsis);
    expect(previa, isNotEmpty, reason: 'prévia com maxLines 3 + ellipsis');
    expect(nota.minimizada, isTrue, reason: 'estado salvo no modelo');

    // Tocar no "•••" da prévia expande.
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(nota.minimizada, isFalse);
  });

  testWidgets('dock segue visível na minimizada; copiar leva o texto inteiro',
      (tester) async {
    await Storage.instance.carregar();
    final nota = Nota(
      id: 'n1',
      texto: List.generate(12, (i) => 'linha ${i + 1}').join('\n'),
    );
    final projeto = Projeto(id: 'p1', nome: 'P', tarefas: [nota]);
    await Storage.instance.substituir([projeto]);

    String? copiado;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiado = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });

    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: projeto)));
    await tester.pumpAndSettle();

    // O topo do projeto também tem um "copiar" (copy_all) na AppBar desde a
    // V0.1.222 — aqui buscamos SÓ o da caixinha (no corpo/TabBarView).
    final copiarCaixa = find.descendant(
        of: find.byType(TabBarView),
        matching: find.byIcon(Icons.copy_all_outlined));

    // Expandida: dock visível à direita (arrastar + copiar).
    expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
    expect(copiarCaixa, findsOneWidget);

    await minimizarPelaBarra(tester);

    // Minimizada: o DOCK continua visível (arrastar/copiar) e a prévia traz
    // o "•••" (expandir).
    expect(find.byIcon(Icons.drag_indicator), findsOneWidget,
        reason: 'o dock continua à direita mesmo na minimizada');
    expect(copiarCaixa, findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);

    // Copiar continua copiando o texto INTEIRO (não só as 3 linhas).
    await tester.tap(copiarCaixa);
    // Aviso "Copiado!" agenda um Timer de 4s — deixa ele disparar.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(copiado, contains('linha 12'));

    // "•••" da prévia expande: o campo de texto volta.
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
    expect(nota.minimizada, isFalse);
  });

  testWidgets('prévia minimizada mostra as 3 primeiras linhas inteiras (sem …)',
      (tester) async {
    await Storage.instance.carregar();
    final nota = Nota(
      id: 'n1',
      texto: List.generate(6, (i) => 'linha ${i + 1}').join('\n'),
    );
    final projeto = Projeto(id: 'p1', nome: 'P', tarefas: [nota]);
    await Storage.instance.substituir([projeto]);

    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: projeto)));
    await tester.pumpAndSettle();
    await minimizarPelaBarra(tester);

    final previa = tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((t) => t.maxLines == 3 && t.overflow == TextOverflow.ellipsis);
    final visivel = previa.textSpan!.toPlainText();
    expect(visivel, 'linha 1\nlinha 2\nlinha 3',
        reason: 'corta na linha exata, sem "…" e sem comer a 3ª linha');
  });

  testWidgets('minimizada mostra os títulos dos links mas esconde o comentário',
      (tester) async {
    await Storage.instance.carregar();
    final nota = Nota(
      id: 'n1',
      texto: List.generate(8, (i) => 'linha ${i + 1}').join('\n'),
      comentario: 'comentário manual',
      links: [NotaLink(url: 'https://youtu.be/abc', titulo: 'Vídeo legal')],
    );
    final projeto = Projeto(id: 'p1', nome: 'P', tarefas: [nota]);
    await Storage.instance.substituir([projeto]);

    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: projeto)));
    await tester.pumpAndSettle();

    await minimizarPelaBarra(tester);

    expect(find.text('Vídeo legal'), findsOneWidget,
        reason: 'título do link continua visível na minimizada');
    expect(find.byType(TextField), findsNothing,
        reason: 'texto principal e comentário ficam escondidos');
  });

  testWidgets('com busca ativa a caixinha minimizada aparece expandida',
      (tester) async {
    await Storage.instance.carregar();
    final nota = Nota(
      id: 'n1',
      texto: List.generate(12, (i) => 'linha ${i + 1}').join('\n'),
      minimizada: true,
    );
    final projeto = Projeto(id: 'p1', nome: 'P', tarefas: [nota]);
    await Storage.instance.substituir([projeto]);

    await tester.pumpWidget(MaterialApp(
      home: ProjetoScreen(
        projeto: projeto,
        termoInicial: 'linha 12',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsWidgets,
        reason: 'busca ativa força a visão expandida (campo montado)');
    expect(nota.minimizada, isTrue,
        reason: 'o estado salvo não muda por causa da busca');
  });
}
