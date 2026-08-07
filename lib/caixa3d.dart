import 'package:flutter/material.dart';

/// Bloco com moldura em degradê nas bordas + sombra, dando um efeito 3D.
/// O contorno vai de um tom mais claro (topo-esquerda) para mais escuro
/// (baixo-direita), como se houvesse relevo.
class Caixa3D extends StatelessWidget {
  const Caixa3D({
    super.key,
    required this.cor,
    required this.child,
    this.raio = 16,
    this.moldura = 2,
  });

  /// Cor principal do conteúdo.
  final Color cor;

  /// Conteúdo que fica dentro da moldura.
  final Widget child;

  /// Raio externo (cantos arredondados).
  final double raio;

  /// Espessura da moldura em degradê.
  final double moldura;

  @override
  Widget build(BuildContext context) {
    final clara = Color.lerp(cor, Colors.white, 0.35)!;
    final escura = Color.lerp(cor, Colors.black, 0.3)!;
    final fundo = Color.lerp(cor, Colors.black, 0.5)!;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [clara, cor, escura],
        ),
        borderRadius: BorderRadius.circular(raio),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: fundo.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      padding: EdgeInsets.all(moldura),
      child: Container(
        decoration: BoxDecoration(
          color: cor,
          borderRadius: BorderRadius.circular(raio - moldura),
        ),
        child: child,
      ),
    );
  }
}