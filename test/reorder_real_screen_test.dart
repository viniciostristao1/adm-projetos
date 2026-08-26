import 'dart:io';

import 'package:adm_projetos/models.dart';
import 'package:adm_projetos/projetos_screen.dart';
import 'package:adm_projetos/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Teste do WIDGET REAL `ProjetosScreen` + Storage real: reproduz o bug em que,
/// com um projeto EM ANDAMENTO (lista em seções), reordenar as pastas de OUTROS
/// não persiste — `_reordenarComSecoes` REATRIBUÍA `_projetos` (quebrando a
/// referência compartilhada com o Storage), o `salvar()` gravava a ordem antiga
/// e o `notifyListeners()` revertia a tela. Sem seção, `_reordenar` muta no
/// lugar e funciona (por isso só quebrava com projeto em andamento).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('adm_reorder_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return dir.path;
      return null;
    });
  });

  Future<List<String>> ordemSalva() async =>
      (await Storage.instance.carregar()).map((p) => p.nome).toList();

  Future<void> semearEAbrir(WidgetTester tester) async {
    await Storage.instance.carregar();
    await Storage.instance.substituir([
      Projeto(id: 'a', nome: 'A', emAndamento: true),
      Projeto(id: 'c', nome: 'C'),
      Projeto(id: 'd', nome: 'D'),
      Projeto(id: 'e', nome: 'E'),
    ]);
    await tester.pumpWidget(const MaterialApp(home: ProjetosScreen()));
    await tester.pumpAndSettle();
    // Alças na ordem da lista: [A(andamento), C, D, E].
    expect(find.byIcon(Icons.drag_indicator), findsNWidgets(4),
        reason: '1 andamento + 3 outros');
  }

  /// Arrasta a alça de índice [iAlca] até a 2ª metade (dy>0) ou 1ª metade
  /// (dy<0) da linha da pasta [destino].
  Future<void> arrastar(
      WidgetTester tester, int iAlca, String destino, double offset) async {
    final alca = find.byIcon(Icons.drag_indicator).at(iAlca);
    final alvoY = tester.getCenter(find.text(destino)).dy + offset;
    final g = await tester.startGesture(tester.getCenter(alca));
    await tester.pump(const Duration(milliseconds: 200));
    await g.moveBy(const Offset(0, 6));
    await tester.pump(const Duration(milliseconds: 20));
    final dist = alvoY - tester.getCenter(alca).dy;
    for (var k = 0; k < 12; k++) {
      await g.moveBy(Offset(0, dist / 12));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets('com EM ANDAMENTO: descer C em OUTROS persiste (não reverte)',
      (tester) async {
    await semearEAbrir(tester);
    await arrastar(tester, 1, 'D', 15); // C (alça 1) para baixo de D
    expect(await ordemSalva(), ['A', 'D', 'C', 'E'],
        reason: 'C deveria descer abaixo de D dentro de OUTROS e PERSISTIR');
  });

  testWidgets('com EM ANDAMENTO: subir E em OUTROS persiste (não reverte)',
      (tester) async {
    await semearEAbrir(tester);
    await arrastar(tester, 3, 'D', -15); // E (alça 3) para cima de D
    expect(await ordemSalva(), ['A', 'C', 'E', 'D'],
        reason: 'E deveria subir acima de D dentro de OUTROS e PERSISTIR');
  });
}
