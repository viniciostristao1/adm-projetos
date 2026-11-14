import 'dart:io';

import 'package:adm_projetos/cores.dart';
import 'package:adm_projetos/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Barra inferior do HomeShell (V0.1.227): sem overflow, altura reduzida e
/// alvos de toque >= 48dp (com e sem a aba Muse).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('adm_barra_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return dir.path;
      return null;
    });
  });

  Future<void> abrirBarra(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(),
        extensions: const [AppCores.azul],
      ),
      home: const HomeShell(),
    ));
    // Frames fixos (a Muse "respira" em loop e o pumpAndSettle nunca acaba).
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('barra sem overflow e com altura reduzida', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await abrirBarra(tester);
    expect(tester.takeException(), isNull);

    final barra = find.byType(BackdropFilter);
    expect(barra, findsOneWidget);
    final size = tester.getSize(barra);
    expect(size.height, lessThanOrEqualTo(58));

    // Alvos de toque: cada InkWell DENTRO da barra tem >= 48 de altura.
    final barraBox = find.byType(BackdropFilter);
    final inkwells = find.descendant(
      of: barraBox,
      matching: find.byType(InkWell),
    );
    expect(inkwells, findsWidgets);
    for (final el in inkwells.evaluate()) {
      final s = tester.getSize(find.byWidget(el.widget));
      expect(s.height, greaterThanOrEqualTo(48), reason: 'alvo: $s');
    }
    // Muse: área do GestureDetector >= 48x48.
    final gestos = find.descendant(
      of: barraBox,
      matching: find.byType(GestureDetector),
    );
    expect(gestos, findsWidgets);
    for (final el in gestos.evaluate()) {
      final s = tester.getSize(find.byWidget(el.widget));
      expect(s.width, greaterThanOrEqualTo(48), reason: 'muse: $s');
      expect(s.height, greaterThanOrEqualTo(48), reason: 'muse: $s');
    }
  });
}
