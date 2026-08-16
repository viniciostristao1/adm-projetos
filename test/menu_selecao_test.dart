import 'dart:io';

import 'package:adm_projetos/models.dart';
import 'package:adm_projetos/projeto_screen.dart';
import 'package:adm_projetos/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regressão do menu de seleção: os botões (copiar/colar/cortar) têm label
/// e o menu abre ACIMA da seleção (não cobrindo as ALÇAS de arrastar, que
/// ficam abaixo do texto — senão não dá para estender a seleção).
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

  testWidgets('selecionar texto mostra o menu de copiar/colar acima',
      (tester) async {
    final p = Projeto(
      id: 'p1',
      nome: 'Projeto A',
      tarefas: [Nota(id: 'n1', texto: 'uma palavra aqui')],
    );
    await Storage.instance.carregar();
    await Storage.instance.substituir([p]);
    await tester.pumpWidget(MaterialApp(home: ProjetoScreen(projeto: p)));
    await tester.pump();

    final field = find.byType(TextField).first;
    // Long press sobre a primeira palavra: seleciona e pede o menu.
    await tester.longPressAt(tester.getTopLeft(field) + const Offset(24, 20));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'menu sem exceção');
    final tf = tester.widget<TextField>(field);
    expect(tf.controller!.selection.isCollapsed, isFalse,
        reason: 'o long-press deve criar uma seleção');

    // Botões com LABEL real (não podem ficar em branco).
    final botao = find.text('Copy');
    expect(botao, findsOneWidget, reason: 'botão copiar com label');

    // Menu ACIMA da seleção: o menu fica acima do ponto tocado (onde nascem
    // as alças de arrastar), deixando-as livres para estender a seleção.
    final rect = tester.getRect(botao.first);
    final pontoSelecao = tester.getTopLeft(field).dy + 20;
    debugPrint('ponto seleção y: $pontoSelecao | rect botão: $rect');
    expect(rect.top, lessThan(pontoSelecao),
        reason: 'menu acima da seleção (não cobre as alças de arrastar)');
  });
}
