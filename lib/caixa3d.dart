import 'package:flutter/material.dart';

/// Bloco com profundidade (3D) vinda de FORA: sombra escura embaixo-direita e
/// um leve brilho claro no topo-esquerda. O próprio bloco é de cor lisa, sem
/// moldura nem degradê em cima dele.
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
    final sombraEscura = Color.lerp(cor, Colors.black, 0.35)!;
    final brilhoClaro = Color.lerp(cor, Colors.white, 0.45)!;
    return Container(
      decoration: BoxDecoration(
        color: cor,
        borderRadius: BorderRadius.circular(raio),
        boxShadow: [
          BoxShadow(
            color: sombraEscura.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: brilhoClaro.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(-3, -3),
          ),
        ],
      ),
      child: child,
    );
  }
}