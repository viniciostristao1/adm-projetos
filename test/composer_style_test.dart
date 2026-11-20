import 'dart:ui';

import 'package:adm_projetos/chat/composer_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// O visual da caixa é FIXO (sem ramo de foco/teclado): estes testes travam os
/// números para nenhuma mudança futura alterar o estilo sem querer.
void main() {
  group('EstiloCaixaComposer (visual fixo)', () {
    test('fundo a 90% com borda 26px', () {
      final d = EstiloCaixaComposer.decoracao(
        const ColorScheme.light(),
        Colors.red,
      );
      expect(d.color!.a, closeTo(0.9, 1e-9));
      expect(d.borderRadius, BorderRadius.circular(26));
    });

    test('vidro sempre ligado, com sigma baixo', () {
      expect(EstiloCaixaComposer.sigmaDesfoque, lessThanOrEqualTo(6.0));
      expect(EstiloCaixaComposer.filtroVidro(), isA<ImageFilter>());
    });
  });
}
