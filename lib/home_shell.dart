import 'package:flutter/material.dart';

import 'chat/chat_config.dart';
import 'chat/conversas_screen.dart';
import 'cores.dart';
import 'models.dart';
import 'muse_blob.dart';
import 'nav_bus.dart';
import 'projeto_screen.dart';
import 'projetos_screen.dart';
import 'storage.dart';

/// Casca do app (V0.1.173): três destinos numa BARRA FLUTUANTE inferior —
/// **Projetos** · **Muse** (centro) · **Estudos**. Substitui a prateleira de
/// acessos rápidos do topo. Abrir um projeto ou uma conversa empilha uma rota
/// cheia (a barra some, foco na tela); voltar traz a barra.
///
/// A aba **Muse** só existe com a flag `CHAT` (`ChatConfig.habilitado`, const de
/// compilação) — sem ela, a casca mostra só Projetos · Estudos, e o código do
/// chat é removido pela árvore morta.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

enum _Aba { projetos, muse, estudos }

class _HomeShellState extends State<HomeShell> {
  int _i = 0;

  /// true quando a aba Estudos está na RAIZ (grade). O PopScope externo só
  /// troca de aba nesse caso — senão os DOIS PopScopes (externo + interno)
  /// disparariam juntos e o gesto cairia em Projetos em vez da grade.
  final ValueNotifier<bool> _estudosNaRaiz = ValueNotifier<bool>(true);

  List<_Aba> get _abas => [
    _Aba.projetos,
    if (ChatConfig.habilitado) _Aba.muse,
    _Aba.estudos,
  ];

  @override
  void initState() {
    super.initState();
    // Permite abrir a aba Muse (com a barra) de qualquer tela (ex.: atalho da
    // Muse dentro de um projeto, que antes abria a lista SEM a barra). V0.1.181.
    abrirAbaMuse = _abrirAbaMuse;
  }

  @override
  void dispose() {
    if (abrirAbaMuse == _abrirAbaMuse) abrirAbaMuse = null;
    _estudosNaRaiz.dispose();
    super.dispose();
  }

  void _abrirAbaMuse() {
    final i = _abas.indexOf(_Aba.muse);
    if (i >= 0) _irPara(i);
  }

  void _irPara(int i) {
    if (i == _i) return;
    setState(() => _i = i);
  }

  Widget _tela(_Aba aba) {
    switch (aba) {
      case _Aba.projetos:
        return const ProjetosScreen();
      case _Aba.muse:
        // Guarda pela flag (além do filtro em _abas) p/ manter o chat removível
        // pela árvore morta num build sem CHAT.
        return ChatConfig.habilitado
            ? const ConversasScreen()
            : const SizedBox.shrink();
      case _Aba.estudos:
        return _EstudosTab(
          onVoltarNaRaiz: () => _irPara(0),
          naRaiz: _estudosNaRaiz,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final abas = _abas;
    // Cor do fundo REAL da tela (nos temas planos vem do scaffoldBackgroundColor;
    // casa com o fade da base p/ não criar uma faixa de cor diferente).
    final fundoTela = Theme.of(context).scaffoldBackgroundColor;
    // Voltar do sistema: fora da aba Projetos, volta para ela; nela, sai do app.
    // Na aba Estudos com algo aberto (pasta), o PopScope INTERNO trata (volta
    // à grade) e este externo fica quieto — senão os dois disparavam juntos.
    return PopScope(
      canPop: _i == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !mounted) return;
        final naRaizEstudos =
            _abas[_i] != _Aba.estudos || _estudosNaRaiz.value;
        if (naRaizEstudos) _irPara(0);
      },
      child: Scaffold(
        // Conteúdo passa ATRÁS da barra flutuante (não corta seco): o corpo vai até
        // o fim da tela e some por baixo da barra com um fade. `extendBody` também
        // injeta o padding da barra no MediaQuery, então os FABs/SafeArea das abas
        // sobem sozinhos p/ não ficar atrás dela. (V0.1.202)
        extendBody: true,
        body: Stack(
          children: [
            IndexedStack(index: _i, children: [for (final a in abas) _tela(a)]),
            // Fade na base: o conteúdo esmaece ao passar atrás da barra flutuante,
            // casando com a ponta escura do fundo (fundoFim). Não captura toque.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 96,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [fundoTela.withValues(alpha: 0), fundoTela],
                      stops: const [0, 0.85],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _BarraFlutuante(
          abas: abas,
          indice: _i,
          onSelecionar: _irPara,
        ),
      ),
    );
  }
}

/// Barra inferior com contorno próprio (flutua, não cola no fundo).
class _BarraFlutuante extends StatelessWidget {
  const _BarraFlutuante({
    required this.abas,
    required this.indice,
    required this.onSelecionar,
  });

  final List<_Aba> abas;
  final int indice;
  final ValueChanged<int> onSelecionar;

  @override
  Widget build(BuildContext context) {
    final app = Theme.of(context).extension<AppCores>() ?? AppCores.azul;
    final cs = Theme.of(context).colorScheme;
    // Temas "planos" (Ônix) usam borda de 1px em vez de sombra forte.
    // Os claros com cartões brancos (Creme/Papel) também: sombra preta sobre
    // fundo claro vaza para fora da barra e parece defeito.
    final plano = app == AppCores.onix ||
        app == AppCores.creme ||
        app == AppCores.papel;
    final fundoBarra = plano
        ? app.barraFerramentas
        : Color.alphaBlend(cs.onSurface.withValues(alpha: 0.04), cs.surface);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: Container(
          height: 64,
          // SEM clip aqui: o botão central elevado ultrapassa o topo (o clip
          // vive no ClipRRect interno da fileira, que contém os respingos).
          decoration: BoxDecoration(
            color: fundoBarra,
            borderRadius: BorderRadius.circular(30),
            border: plano
                ? Border.all(color: cs.outlineVariant.withValues(alpha: 0.7))
                : null,
            boxShadow: plano
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: _conteudoBarra(context, app, cs),
        ),
      ),
    );
  }

  /// Conteúdo da barra: com a aba Muse, o avatar vai NO MEIO da fileira,
  /// centralizado verticalmente com os ícones (sem elevar nem sobressair).
  /// Sem Muse (build sem CHAT), fileira simples com as abas que houver.
  Widget _conteudoBarra(
      BuildContext context, AppCores app, ColorScheme cs) {
    final iMuse = abas.indexOf(_Aba.muse);
    if (iMuse < 0) {
      return Row(
        children: [
          for (var i = 0; i < abas.length; i++)
            Expanded(
              child: _ItemBarra(
                aba: abas[i],
                selecionado: i == indice,
                acento: app.fab,
                inativo: cs.onSurfaceVariant,
                onTap: () => onSelecionar(i),
              ),
            ),
        ],
      );
    }
    Widget lado(int i) => Expanded(
          child: _ItemBarra(
            aba: abas[i],
            selecionado: i == indice,
            acento: app.fab,
            inativo: cs.onSurfaceVariant,
            onTap: () => onSelecionar(i),
          ),
        );
    // Rosto recortado do PNG (corta o anel laranja da borda): ocupa quase
    // todo o círculo de 56px, sem anéis empilhados, em todos os temas.
    Widget muse() => Tooltip(
          message: 'Muse Spark (assistente)',
          child: GestureDetector(
            onTap: () => onSelecionar(iMuse),
            child: SizedBox(
              width: 56,
              height: 56,
              child: ClipOval(
                child: OverflowBox(
                  maxWidth: 72,
                  maxHeight: 72,
                  child: MuseBlob(size: 72),
                ),
              ),
            ),
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < abas.length; i++)
          if (i != iMuse) lado(i) else muse(),
      ],
    );
  }
}

class _ItemBarra extends StatelessWidget {
  const _ItemBarra({
    required this.aba,
    required this.selecionado,
    required this.acento,
    required this.inativo,
    required this.onTap,
  });

  final _Aba aba;
  final bool selecionado;
  final Color acento;
  final Color inativo;
  final VoidCallback onTap;

  String get _rotulo => switch (aba) {
    _Aba.projetos => 'Projetos',
    _Aba.muse => 'Muse',
    _Aba.estudos => 'Estudos',
  };

  @override
  Widget build(BuildContext context) {
    final cor = selecionado ? acento : inativo;
    Widget icone;
    if (aba == _Aba.muse) {
      // Rosto da Muse, um pouco maior e mais nítido; esmaece de leve quando a
      // aba não está ativa. (V0.1.181)
      icone = Opacity(
        opacity: selecionado ? 1 : 0.8,
        child: const MuseBlob(size: 32),
      );
    } else {
      icone = Icon(
        aba == _Aba.projetos ? Icons.folder_outlined : Icons.menu_book_outlined,
        size: 24,
        color: cor,
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pílula de destaque atrás do ícone da aba ativa.
            Container(
              height: 36,
              width: 56,
              alignment: Alignment.center,
              decoration: selecionado
                  ? BoxDecoration(
                      color: acento.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    )
                  : null,
              child: icone,
            ),
            const SizedBox(height: 3),
            Text(
              _rotulo,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selecionado ? FontWeight.w700 : FontWeight.w500,
                color: cor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aba "Estudos": o projeto reservado "Estudos" embutido (modo pastas). Cria-o
/// na 1ª vez. É onde o usuário cola resumos/mensagens da Muse.
class _EstudosTab extends StatefulWidget {
  const _EstudosTab({required this.onVoltarNaRaiz, required this.naRaiz});
  final VoidCallback onVoltarNaRaiz;
  final ValueNotifier<bool> naRaiz;

  @override
  State<_EstudosTab> createState() => _EstudosTabState();
}

class _EstudosTabState extends State<_EstudosTab> {
  static const String _nome = 'Estudos';
  Projeto? _proj;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final projetos = await Storage.instance.carregar();
    Projeto? achado;
    for (final p in projetos) {
      if (p.nome == _nome) {
        achado = p;
        break;
      }
    }
    if (achado == null) {
      achado = Projeto(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        nome: _nome,
      );
      projetos.add(achado);
      await Storage.instance.salvar();
    }
    if (!mounted) return;
    setState(() => _proj = achado);
  }

  @override
  Widget build(BuildContext context) {
    final proj = _proj;
    if (proj == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // key por id: se o projeto for recriado, remonta a tela.
    return ProjetoScreen(
      key: ValueKey('estudos_${proj.id}'),
      projeto: proj,
      modoPastasInicial: true,
      embutido: true,
      onVoltarNaRaiz: widget.onVoltarNaRaiz,
      onNaGradeMudou: (v) => widget.naRaiz.value = v,
    );
  }
}
