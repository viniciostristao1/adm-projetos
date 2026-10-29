import 'package:flutter/material.dart';

import 'cores.dart';

/// Rosto da Muse Spark: a mascote (personagem rosa de óculos com o tablet) que
/// identifica o assistente — na barra inferior, na lista de conversas, no título
/// do chat e no atalho dentro do projeto.
///
/// É uma IMAGEM (V0.1.178, arte do usuário em `assets/muse/`). A IDENTIDADE (a
/// personagem rosa) é a mesma em todos os temas; o que muda por tema é o **anel
/// neon** (contorno), recolorido no acento de cada tema — ideia do usuário.
/// O asset certo é escolhido pelo tema atual (`AppCores`). Fica FORA de
/// `lib/chat/` de propósito, para a barra usar sem arrastar o código do chat.
class MuseBlob extends StatelessWidget {
  const MuseBlob({super.key, this.size = 32});

  final double size;

  /// Mapeia o tema (AppCores) → nome do asset do anel.
  static String _nomeTema(AppCores app) {
    if (app == AppCores.escuro) return 'escuro';
    if (app == AppCores.neumB) return 'darkgame';
    if (app == AppCores.bege) return 'bege';
    if (app == AppCores.claude) return 'terracota';
    if (app == AppCores.onix) return 'onix';
    if (app == AppCores.luz) return 'claro';
    return 'azul';
  }

  @override
  Widget build(BuildContext context) {
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.azul;
    return Image.asset(
      'assets/muse/muse_${_nomeTema(app)}.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
      // Reserva: se o asset faltar, um círculo no acento (nunca quebra a UI).
      errorBuilder: (_, _, _) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: app.fab, shape: BoxShape.circle),
      ),
    );
  }
}

/// Muse "respirando + brilho" (V0.1.184): escala pulsando devagar + o anel neon
/// (glow na cor de acento do tema) pulsando junto. SEMPRE animada — usada no topo
/// da lista de conversas. Respeita "reduzir movimento" do sistema.
class MuseRespira extends StatefulWidget {
  const MuseRespira({super.key, this.size = 72});
  final double size;

  @override
  State<MuseRespira> createState() => _MuseRespiraState();
}

class _MuseRespiraState extends State<MuseRespira>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blob = MuseBlob(size: widget.size);
    if (MediaQuery.of(context).disableAnimations) return blob;
    final acc = (Theme.of(context).extension<AppCores>() ?? AppCores.azul).fab;
    return AnimatedBuilder(
      animation: _c,
      child: blob,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value); // 0..1
        return Transform.scale(
          scale: 1.0 + 0.06 * t,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: acc.withValues(alpha: 0.12 + 0.55 * t),
                  blurRadius: 5 + 20 * t,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// "Pula" (V0.1.184): dá pulinhos com squash/stretch ENQUANTO [ativo] (a Muse
/// pensando no chat); parado quando ocioso. Envolve qualquer [child] (ex.: o dot
/// do modo no botão de enviar). Respeita "reduzir movimento".
class MusePula extends StatefulWidget {
  const MusePula(
      {super.key, required this.ativo, required this.size, required this.child});
  final bool ativo;
  final double size;
  final Widget child;

  @override
  State<MusePula> createState() => _MusePulaState();
}

class _MusePulaState extends State<MusePula>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1050));

  // translateY: fica no chão, sobe no meio, volta.
  static final _ty = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 15),
    TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -12.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30),
    TweenSequenceItem(
        tween: Tween(begin: -12.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 25),
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 30),
  ]);
  // scaleY: agacha (squash), estica no ar, amortece, volta.
  static final _sy = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.88), weight: 15),
    TweenSequenceItem(tween: Tween(begin: 0.88, end: 1.05), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 1.05, end: 0.94), weight: 25),
    TweenSequenceItem(tween: Tween(begin: 0.94, end: 1.0), weight: 30),
  ]);

  @override
  void initState() {
    super.initState();
    if (widget.ativo) _c.repeat();
  }

  @override
  void didUpdateWidget(MusePula old) {
    super.didUpdateWidget(old);
    if (widget.ativo && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.ativo && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box =
        SizedBox(width: widget.size, height: widget.size, child: widget.child);
    if (!widget.ativo || MediaQuery.of(context).disableAnimations) return box;
    return AnimatedBuilder(
      animation: _c,
      child: box,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _ty.evaluate(_c)),
          child: Transform.scale(
            scaleY: _sy.evaluate(_c),
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        );
      },
    );
  }
}
