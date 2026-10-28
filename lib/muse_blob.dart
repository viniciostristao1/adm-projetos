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
      filterQuality: FilterQuality.medium,
      // Reserva: se o asset faltar, um círculo no acento (nunca quebra a UI).
      errorBuilder: (_, _, _) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: app.fab, shape: BoxShape.circle),
      ),
    );
  }
}
