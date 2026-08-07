import 'package:flutter/material.dart';

import 'cores.dart';

/// Título dentro de um retângulo arredondado com a cor do tema
/// (âmbar no escuro, marrom no bege, azul no claro).
class TituloDestacado extends StatelessWidget {
  const TituloDestacado(
    this.texto, {
    super.key,
    this.cor,
    this.corTexto,
    this.estilo,
  });

  final String texto;
  final Color? cor;
  final Color? corTexto;
  final TextStyle? estilo;

  @override
  Widget build(BuildContext context) {
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.luz;
    final contorno = cor ?? app.fab;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: contorno.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: contorno, width: 1.4),
      ),
      child: Text(
        texto,
        style: estilo?.copyWith(
              color: corTexto ?? Theme.of(context).colorScheme.onSurface,
            ) ??
            TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: corTexto ?? Theme.of(context).colorScheme.onSurface,
            ),
      ),
    );
  }
}