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

  testWidgets('botão ••• minimiza (3 linhas com reticências) e expande',
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

    final botao = find.byIcon(Icons.more_horiz);
    await tester.ensureVisible(botao);
    await tester.pumpAndSettle();
    await tester.tap(botao);
    await tester.pumpAndSettle();

    // Minimizada: o campo some e aparece a prévia de 3 linhas com reticências.
    expect(find.byType(TextField), findsNothing);
    final previa = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.maxLines == 3 && t.overflow == TextOverflow.ellipsis);
    expect(previa, isNotEmpty, reason: 'prévia com maxLines 3 + ellipsis');
    expect(nota.minimizada, isTrue, reason: 'estado salvo no modelo');

    // Tocar de novo (no botão) expande.
    await tester.tap(botao);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(nota.minimizada, isFalse);
  });

  testWidgets('minimizada oculta a barra e põe copiar + ••• no fim da 3ª linha',
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

    // Expandida: barra de ferramentas visível (pino de arrastar + copiar).
    expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
    expect(find.byIcon(Icons.copy_all_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    // Minimizada: barra OCULTA e botões copiar + "•••" no fim do texto.
    expect(find.byIcon(Icons.drag_indicator), findsNothing,
        reason: 'a barra de ferramentas some na minimizada');
    expect(find.byIcon(Icons.copy_all_outlined), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);

    // Copiar continua copiando o texto INTEIRO (não só as 3 linhas).
    await tester.tap(find.byIcon(Icons.copy_all_outlined));
    // Aviso "Copiado!" agenda um Timer de 4s — deixa ele disparar.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(copiado, contains('linha 12'));

    // "•••" expande: o campo de texto e a barra voltam.
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
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

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

    final botao = find.byIcon(Icons.more_horiz);
    await tester.ensureVisible(botao);
    await tester.pumpAndSettle();
    await tester.tap(botao);
    await tester.pumpAndSettle();

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
