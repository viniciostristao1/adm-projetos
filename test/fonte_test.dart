import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('subset NotoSansSymbols2 embutido renderiza os quadradinhos',
      (tester) async {
    final data =
        await rootBundle.load('assets/fonts/NotoSansSymbols2-Regular.ttf');
    final loader = FontLoader('NotoSansSymbols2')..addFont(Future.value(data));
    await loader.load();

    double largura(String texto, {bool comFallback = true}) {
      final p = TextPainter(
        text: TextSpan(
          text: texto,
          style: TextStyle(
            fontSize: 14.5,
            fontFamilyFallback: comFallback ? const ['NotoSansSymbols2'] : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      return p.width;
    }

    final larguraAhem = largura('☑', comFallback: false);
    final larguraComFonte = largura('☑');
    debugPrint('largura sem fallback: $larguraAhem | com fallback: $larguraComFonte');

    // A fonte embutida foi consultada (métrica diferente da fonte de teste).
    expect(larguraComFonte, isNot(closeTo(larguraAhem, 0.1)));

    // O ☑ (U+2611) tem glifo real (largura ~0.9em, não tofu .notdef).
    expect(larguraComFonte, greaterThan(8));
    expect(larguraComFonte, lessThan(16));

    for (final c in ['☐', '☑', '☒']) {
      final w = largura(c);
      expect(w, greaterThan(8), reason: '$c deve ter glifo real');
      expect(w, lessThan(16), reason: '$c deve ter glifo real');
    }
  });
}
