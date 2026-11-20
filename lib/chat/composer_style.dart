import 'dart:ui';

import 'package:flutter/material.dart';

/// Estilo FIXO da caixa de digitação do chat (flutuante sobre a conversa).
///
/// Propositalmente SEM nenhum parâmetro de foco/teclado/digitação: o visual é
/// idêntico em repouso, com foco, digitando, com teclado aberto ou fechado.
/// Ajuste por estado (ex.: compensar o teclado) acontece SÓ no espaço
/// inferior da lista, nunca aqui.
class EstiloCaixaComposer {
  /// Opacidade do fundo da caixa (o texto de trás aparece discreto).
  static const double opacidadeFundo = 0.9;

  /// Desfoque do vidro (baixo p/ não pesar em celular modesto). Sempre ligado.
  static const double sigmaDesfoque = 4.0;

  static BoxDecoration decoracao(ColorScheme cs, Color corBorda) =>
      BoxDecoration(
        color: cs.surface.withValues(alpha: opacidadeFundo),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: corBorda.withValues(alpha: 0.35)),
      );

  static ImageFilter filtroVidro() => ImageFilter.blur(
        sigmaX: sigmaDesfoque,
        sigmaY: sigmaDesfoque,
      );
}
