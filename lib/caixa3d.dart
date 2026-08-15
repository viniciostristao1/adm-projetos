import 'package:flutter/material.dart';

import 'cores.dart';

/// Bloco com cantos arredondados e cor lisa (temas planos) ou superfície
/// neumórfica em relevo (temas A e B): gradiente sutil, luz vinda do canto
/// superior esquerdo, sombra dupla difusa e highlight discreto no topo/esquerda.
class Caixa3D extends StatelessWidget {
  const Caixa3D({
    super.key,
    required this.cor,
    required this.child,
    this.raio = 14,
    this.corInicio,
    this.corFim,
  });

  /// Cor principal (lisa) do bloco nos temas planos.
  final Color cor;

  /// Conteúdo do bloco.
  final Widget child;

  /// Raio dos cantos arredondados.
  final double raio;

  /// Nos temas neumórficos, sobrescrevem as pontas do gradiente da
  /// superfície (padrão: notaInicio → notaFim do tema).
  final Color? corInicio;
  final Color? corFim;

  @override
  Widget build(BuildContext context) {
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.azul;
    if (!app.neumorfico) {
      return Container(
        decoration: BoxDecoration(
          color: cor,
          borderRadius: BorderRadius.circular(raio),
        ),
        child: child,
      );
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(raio),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            corInicio ?? app.notaInicio,
            corFim ?? app.notaFim,
          ],
        ),
        boxShadow: [
          // sombra principal (abaixo/direita) — distante e difusa
          BoxShadow(
            color: app.sombraForte,
            offset: const Offset(7, 9),
            blurRadius: 18,
            spreadRadius: -4,
          ),
          // sombra de proximidade (âncora)
          BoxShadow(
            color: app.sombraFraca,
            offset: const Offset(2, 3),
            blurRadius: 8,
            spreadRadius: -2,
          ),
          // luz difusa refletida (acima/esquerda)
          BoxShadow(
            color: app.brilho,
            offset: const Offset(-6, -6),
            blurRadius: 16,
            spreadRadius: -8,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Botão/elemento interativo neumórfico: elevado no estado normal e
/// "pressionado para dentro" ao tocar (inner shadow simulada por gradiente).
/// [selecionado] mantém o estado pressionado com um leve tint do acento.
/// Nos temas planos, apenas repassa o toque ao [child] sem decoração.
class BotaoNeum extends StatefulWidget {
  const BotaoNeum({
    super.key,
    required this.child,
    this.onTap,
    this.raio = 12,
    this.selecionado = false,
    this.tooltip,
    this.padding = const EdgeInsets.all(7),
    this.corInicio,
    this.corFim,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double raio;
  final bool selecionado;
  final String? tooltip;
  final EdgeInsetsGeometry padding;

  /// Sobrescrevem as pontas do gradiente da superfície (padrão: as do tema).
  final Color? corInicio;
  final Color? corFim;

  @override
  State<BotaoNeum> createState() => _BotaoNeumState();
}

class _BotaoNeumState extends State<BotaoNeum> {
  bool _pressionado = false;

  @override
  Widget build(BuildContext context) {
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.azul;
    if (!app.neumorfico) {
      return GestureDetector(onTap: widget.onTap, child: widget.child);
    }
    final inset = _pressionado || widget.selecionado;
    Widget w = AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.raio),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            widget.corInicio ?? app.notaInicio,
            widget.corFim ?? app.notaFim,
          ],
        ),
        boxShadow: inset
            ? const []
            : [
                BoxShadow(
                  color: app.sombraFraca,
                  offset: const Offset(3, 4),
                  blurRadius: 8,
                  spreadRadius: -2,
                ),
                BoxShadow(
                  color: app.brilho,
                  offset: const Offset(-3, -3),
                  blurRadius: 7,
                  spreadRadius: -4,
                ),
              ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.raio),
          gradient: inset
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    app.sombraForte,
                    widget.selecionado
                        ? app.fab.withValues(alpha: 0.14)
                        : Colors.transparent,
                    app.brilho,
                  ],
                  stops: const [0, 0.5, 1],
                )
              : null,
        ),
        child: widget.child,
      ),
    );
    if (widget.tooltip != null) {
      w = Tooltip(message: widget.tooltip!, child: w);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressionado = true),
      onTapUp: (_) => setState(() => _pressionado = false),
      onTapCancel: () => setState(() => _pressionado = false),
      onTap: widget.onTap,
      child: w,
    );
  }
}

/// Fundo com gradiente dos temas neumórficos, aplicado POR TELA (dentro da
/// rota). Nos temas planos, devolve o [child] sem decoração.
///
/// Fica dentro da rota de propósito: durante a transição de voltar (gesto
/// preditivo), o gradiente participa do fade da página junto com o conteúdo —
/// sem isso a página vira um "fantasma" sobre a anterior.
class Fundo extends StatelessWidget {
  const Fundo({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.azul;
    if (!app.neumorfico) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.7, -1.3),
          radius: 1.6,
          colors: [app.fundoInicio, app.fundoFim],
        ),
      ),
      child: child,
    );
  }
}
