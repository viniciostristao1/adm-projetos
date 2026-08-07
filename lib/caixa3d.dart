import 'package:flutter/material.dart';

/// Bloco simples com cantos arredondados e cor lisa (sem sombra nem
/// brilho colorido — sem visual "neon" em volta).
class Caixa3D extends StatelessWidget {
  const Caixa3D({
    super.key,
    required this.cor,
    required this.child,
    this.raio = 14,
  });

  /// Cor principal (lisa) do bloco.
  final Color cor;

  /// Conteúdo do bloco.
  final Widget child;

  /// Raio dos cantos arredondados.
  final double raio;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cor,
        borderRadius: BorderRadius.circular(raio),
      ),
      child: child,
    );
  }
}