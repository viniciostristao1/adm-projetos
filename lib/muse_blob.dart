import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'cores.dart';

/// Rosto da Muse Spark: um blob vítreo (esfera com brilho + "fones" laterais +
/// dois olhos). É o mascote do assistente, usado na barra inferior, na lista de
/// conversas e na pílula de status.
///
/// Fica FORA do módulo `lib/chat/` de propósito: é só um desenho (CustomPainter),
/// sem nenhuma dependência do chat, para a barra de navegação poder exibi-lo sem
/// arrastar o código do chat (que é separável pela flag CHAT).
///
/// A cor segue o ACENTO do tema (`AppCores.fab`) por padrão — um blob por tema,
/// como os glifos do app. Passe [cor] para fixar uma cor.
class MuseBlob extends StatelessWidget {
  const MuseBlob({super.key, this.size = 32, this.cor, this.halo = true});

  final double size;
  final Color? cor;

  /// Halo externo suave. Em ícones pequenos (barra) fica mais limpo sem ele.
  final bool halo;

  @override
  Widget build(BuildContext context) {
    final acc = cor ??
        (Theme.of(context).extension<AppCores>() ?? AppCores.azul).fab;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BlobPainter(acc, halo)),
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.acc, this.halo);
  final Color acc;
  final bool halo;

  static Color _dark(Color c, double k) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness * k).clamp(0.0, 1.0)).toColor();
  }

  static Color _mix(Color c, Color o, double t) => Color.lerp(c, o, t)!;

  @override
  void paint(Canvas canvas, Size size) {
    // Geometria autoral no espaço 1024×1024 (mesma dos mockups), reescalada.
    final s = size.width / 1024.0;
    Offset p(double x, double y) => Offset(x * s, y * s);
    double r(double v) => v * s;

    final hi = _mix(acc, Colors.white, 0.80);
    final lite = _mix(acc, Colors.white, 0.40);
    final mid = acc;
    final edge = _dark(acc, 0.58);
    final deep = _dark(acc, 0.78);
    final wing1 = _dark(acc, 0.62);
    final wingMid = _dark(acc, 0.42);
    final wing2 = _dark(acc, 0.30);
    final haloCor = _mix(acc, Colors.white, 0.55);

    // Halo externo.
    if (halo) {
      final haloRect = Rect.fromCircle(center: p(512, 530), radius: r(400));
      final haloPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            haloCor.withValues(alpha: 0),
            haloCor.withValues(alpha: 0.22),
            haloCor.withValues(alpha: 0),
          ],
          stops: const [0.66, 0.90, 1.0],
        ).createShader(haloRect);
      canvas.drawCircle(p(512, 530), r(400), haloPaint);
    }

    // "Fones"/asas laterais (atrás do corpo), com leve rotação.
    void wing(double x, double y, double w, double h, double cx, double cy,
        double graus) {
      canvas.save();
      canvas.translate(cx * s, cy * s);
      canvas.rotate(graus * math.pi / 180);
      final rect =
          Rect.fromLTWH((x - cx) * s, (y - cy) * s, w * s, h * s);
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [wing1, wingMid, wing2],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(r(75))), paint);
      canvas.restore();
    }

    wing(150, 408, 150, 235, 225, 525, -16);
    wing(724, 408, 150, 235, 799, 525, 16);

    // Corpo: esfera com brilho no topo-esquerda.
    final corpoRect = Rect.fromCircle(center: p(512, 530), radius: r(302));
    final corpoPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.20, -0.34), // 40% / 33%
        radius: 0.75,
        colors: [hi, lite, mid, edge, deep],
        stops: const [0.0, 0.22, 0.55, 0.82, 1.0],
      ).createShader(corpoRect);
    canvas.drawCircle(p(512, 530), r(302), corpoPaint);

    // Brilho especular (topo-esquerda), elipse girada.
    canvas.save();
    canvas.translate(408 * s, 372 * s);
    canvas.rotate(-24 * math.pi / 180);
    final specRect = Rect.fromCenter(
        center: Offset.zero, width: 300 * s, height: 220 * s);
    final specPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.95),
          Colors.white.withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(specRect);
    canvas.drawOval(specRect, specPaint);
    canvas.restore();

    // Pontinho de brilho.
    canvas.drawCircle(
        p(372, 340), r(26), Paint()..color = Colors.white.withValues(alpha: 0.9));

    // Olhos (dois pills quase brancos).
    final olhoPaint = Paint()..color = const Color(0xFFF6FAFF);
    for (final ex in [430.0, 538.0]) {
      final rect = Rect.fromLTWH(ex * s, 474 * s, 56 * s, 88 * s);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(r(28))), olhoPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) =>
      old.acc != acc || old.halo != halo;
}
