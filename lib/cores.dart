import 'package:flutter/material.dart';

/// Cores específicas do app por tema (além do colorScheme padrão do Material).
/// Fornecem o gradiente da caixinha de texto, a cor dos cartões de projeto e
/// a cor do botão "+".
@immutable
class AppCores extends ThemeExtension<AppCores> {
  const AppCores({
    required this.notaInicio,
    required this.notaFim,
    required this.notaBorda,
    required this.projetoCard,
    required this.projetoTxt,
    required this.fab,
    required this.fabIcone,
    required this.barraFerramentas,
    this.neumorfico = false,
    this.fundoInicio = const Color(0xFF000000),
    this.fundoFim = const Color(0xFF000000),
    this.sombraForte = const Color(0xB3000000),
    this.sombraFraca = const Color(0x73000000),
    this.brilho = const Color(0x0AFFFFFF),
    this.bordaLuz = const Color(0x14FFFFFF),
    this.projetoCardFim = const Color(0xFF000000),
    this.barraFerramentasFim = const Color(0xFF000000),
    this.textoUI = const Color(0xFFFFFFFF),
  });

  final Color notaInicio;
  final Color notaFim;
  final Color notaBorda;
  final Color projetoCard;
  final Color projetoTxt;
  final Color fab;
  final Color fabIcone;

  /// Cor de fundo da barra de ferramentas (ícones) no topo de cada caixinha.
  final Color barraFerramentas;

  /// Se true, superfícies usam relevo neumórfico (gradiente + luz ↗ esquerda
  /// superior + sombra dupla difusa), em vez de cores lisas.
  final bool neumorfico;

  /// Gradiente do fundo do app (topo-esquerda → baixo-direita).
  final Color fundoInicio;
  final Color fundoFim;

  /// Sombras da luz neumórfica: principal (difusa), de proximidade e a luz
  /// refletida no canto superior esquerdo.
  final Color sombraForte;
  final Color sombraFraca;
  final Color brilho;

  /// Highlight de 1px nas bordas superior/esquerda das superfícies.
  final Color bordaLuz;

  /// Ponta escura do gradiente do cartão de projeto (temas neumórficos).
  final Color projetoCardFim;

  /// Ponta escura do gradiente da barra de ferramentas (temas neumórficos).
  final Color barraFerramentasFim;

  /// Cor do texto da interface (títulos, abas, chips) — pode diferir da cor
  /// do texto dentro dos cartões quando o cartão é escuro e o fundo claro.
  final Color textoUI;

  /// Tema Azul (estilo Calis Timer — navy + accent azul): fundo navy
  /// profundo, superfícies azul-acinzentadas, texto claro. Plano (sem relevo).
  static const AppCores azul = AppCores(
    notaInicio: Color(0xFF121A2E),
    notaFim: Color(0xFF1B2540),
    notaBorda: Color(0x14FFFFFF),
    projetoCard: Color(0xFF121A2E),
    projetoCardFim: Color(0xFF0A0F1C),
    projetoTxt: Color(0xFFEAF0FB),
    fab: Color(0xFF3B82F6),
    fabIcone: Color(0xFFF2F7FF),
    barraFerramentas: Color(0xFF1B2540),
    barraFerramentasFim: Color(0xFF121A2E),
    fundoInicio: Color(0xFF0A0F1C),
    fundoFim: Color(0xFF070B14),
    textoUI: Color(0xFFEAF0FB),
  );

  /// Tema escuro: fundo preto, caixinha cinza escuro, barra de ferramentas mais escura.
  static const AppCores escuro = AppCores(
    notaInicio: Color(0xFF252525),
    notaFim: Color(0xFF252525),
    notaBorda: Color(0x33FFFFFF),
    projetoCard: Colors.black,
    projetoTxt: Colors.white,
    fab: Color(0xFFD48000),
    fabIcone: Color(0xFF1A0E00),
    barraFerramentas: Color(0xFF1A1A1A),
  );

  /// Tema B (Dark Game): grafite e pretos neutros, acento aço desaturado.
  static const AppCores neumB = AppCores(
    notaInicio: Color(0xFF1B1D20),
    notaFim: Color(0xFF111315),
    notaBorda: Color(0x00FFFFFF),
    projetoCard: Color(0xFF1B1D20),
    projetoCardFim: Color(0xFF111315),
    projetoTxt: Color(0xFFEDEFF1),
    fab: Color(0xFF9AA4AE),
    fabIcone: Color(0xFF0D1012),
    barraFerramentas: Color(0xFF111315),
    barraFerramentasFim: Color(0xFF111315),
    neumorfico: true,
    fundoInicio: Color(0xFF121517),
    fundoFim: Color(0xFF0A0C0D),
    sombraForte: Color(0xC0000000),
    sombraFraca: Color(0x80000000),
    brilho: Color(0x08FFFFFF),
    bordaLuz: Color(0x10FFFFFF),
    textoUI: Color(0xFFEDEFF1),
  );

  /// Tema Claude Code: preto-quente sólido (#0C0C0D), superfícies #161617
  /// com borda de 1px (#2A2A2B), acento terracota (#D97757) e fonte
  /// monoespaçada (JetBrains Mono). Plano, sem sombras, estilo terminal.
  static const AppCores claude = AppCores(
    // Um pouquinho mais claras que antes (interior da caixinha #161617→#1E1E20;
    // barra de ferramentas #111213→#18181A) — cada tom clareado em separado,
    // mantendo a barra mais escura que o interior e o fundo (#0C0C0D) o
    // mais escuro de todos.
    notaInicio: Color(0xFF1E1E20),
    notaFim: Color(0xFF1E1E20),
    notaBorda: Color(0xFF2A2A2B),
    projetoCard: Color(0xFF161617),
    projetoCardFim: Color(0xFF161617),
    projetoTxt: Color(0xFFF0EEE9),
    fab: Color(0xFFD97757),
    fabIcone: Color(0xFF120806),
    barraFerramentas: Color(0xFF18181A),
    barraFerramentasFim: Color(0xFF18181A),
    fundoInicio: Color(0xFF0C0C0D),
    fundoFim: Color(0xFF0C0C0D),
    textoUI: Color(0xFFF0EEE9),
  );

  /// Tema Ônix (estilo ChatGPT): preto liso (#0D0D0D), texto branco (#ECECEC)
  /// e um verde discreto (#19C37D) só no accent/botão +. Home sem caixa: o
  /// cartão de projeto é a própria cor do fundo (as pastas viram linhas), e as
  /// bolinhas/recentes usam [notaFim] para aparecerem no preto.
  static const AppCores onix = AppCores(
    notaInicio: Color(0xFF1E1F20),
    notaFim: Color(0xFF26272A),
    notaBorda: Color(0xFF2A2A2B),
    projetoCard: Color(0xFF0D0D0D),
    projetoCardFim: Color(0xFF0D0D0D),
    projetoTxt: Color(0xFFECECEC),
    fab: Color(0xFF19C37D),
    fabIcone: Color(0xFF052B1B),
    barraFerramentas: Color(0xFF171717),
    barraFerramentasFim: Color(0xFF171717),
    fundoInicio: Color(0xFF0D0D0D),
    fundoFim: Color(0xFF0D0D0D),
    textoUI: Color(0xFFECECEC),
  );

  /// Preto das intervenções/botões nos temas claros novos (contraste com o
  /// bege/off-white — vindo das refs estilo Claude do Nestwallet, V0.1.195).
  static const kPretoCremePapel = Color(0xFF1B1B1B);

  /// Tema Creme (V0.1.195) — fundo bege (#F5F0E6), cartões brancos flutuantes,
  /// texto marrom-quase-preto, intervenções/botões PRETOS e detalhe terracota
  /// (#C96F4A). Títulos serifados. Plano. Roda em `ThemeMode.light`.
  static const AppCores creme = AppCores(
    notaInicio: Color(0xFFFFFFFF),
    notaFim: Color(0xFFFFFFFF),
    notaBorda: Color(0x141F1B16),
    projetoCard: Color(0xFFFFFFFF),
    projetoCardFim: Color(0xFFFFFFFF),
    projetoTxt: Color(0xFF1F1B16),
    fab: Color(0xFFC96F4A),
    fabIcone: Color(0xFFFFF6F0),
    barraFerramentas: Color(0xFFEFE7D8),
    barraFerramentasFim: Color(0xFFEFE7D8),
    fundoInicio: Color(0xFFF5F0E6),
    fundoFim: Color(0xFFEFE7D8),
    textoUI: Color(0xFF1F1B16),
  );

  /// Tema Papel (V0.1.195) — fundo off-white (#FAF8F5), cartões brancos
  /// flutuantes, texto quase-preto, intervenções/botões PRETOS e detalhe verde
  /// (#1E9E6A). Títulos serifados. Plano. Roda em `ThemeMode.light`.
  static const AppCores papel = AppCores(
    notaInicio: Color(0xFFFFFFFF),
    notaFim: Color(0xFFFFFFFF),
    notaBorda: Color(0x141A1A1A),
    projetoCard: Color(0xFFFFFFFF),
    projetoCardFim: Color(0xFFFFFFFF),
    projetoTxt: Color(0xFF1A1A1A),
    fab: Color(0xFF1E9E6A),
    fabIcone: Color(0xFFEFFBF4),
    barraFerramentas: Color(0xFFF0EBE4),
    barraFerramentasFim: Color(0xFFF0EBE4),
    fundoInicio: Color(0xFFFAF8F5),
    fundoFim: Color(0xFFF0EBE4),
    textoUI: Color(0xFF1A1A1A),
  );

  @override
  AppCores copyWith({
    Color? notaInicio,
    Color? notaFim,
    Color? notaBorda,
    Color? projetoCard,
    Color? projetoTxt,
    Color? fab,
    Color? fabIcone,
    Color? barraFerramentas,
    bool? neumorfico,
    Color? fundoInicio,
    Color? fundoFim,
    Color? sombraForte,
    Color? sombraFraca,
    Color? brilho,
    Color? bordaLuz,
    Color? projetoCardFim,
    Color? barraFerramentasFim,
    Color? textoUI,
  }) {
    return AppCores(
      notaInicio: notaInicio ?? this.notaInicio,
      notaFim: notaFim ?? this.notaFim,
      notaBorda: notaBorda ?? this.notaBorda,
      projetoCard: projetoCard ?? this.projetoCard,
      projetoTxt: projetoTxt ?? this.projetoTxt,
      fab: fab ?? this.fab,
      fabIcone: fabIcone ?? this.fabIcone,
      barraFerramentas: barraFerramentas ?? this.barraFerramentas,
      neumorfico: neumorfico ?? this.neumorfico,
      fundoInicio: fundoInicio ?? this.fundoInicio,
      fundoFim: fundoFim ?? this.fundoFim,
      sombraForte: sombraForte ?? this.sombraForte,
      sombraFraca: sombraFraca ?? this.sombraFraca,
      brilho: brilho ?? this.brilho,
      bordaLuz: bordaLuz ?? this.bordaLuz,
      projetoCardFim: projetoCardFim ?? this.projetoCardFim,
      barraFerramentasFim:
          barraFerramentasFim ?? this.barraFerramentasFim,
      textoUI: textoUI ?? this.textoUI,
    );
  }

  @override
  AppCores lerp(AppCores? other, double t) {
    if (other == null) return this;
    return AppCores(
      notaInicio: Color.lerp(notaInicio, other.notaInicio, t)!,
      notaFim: Color.lerp(notaFim, other.notaFim, t)!,
      notaBorda: Color.lerp(notaBorda, other.notaBorda, t)!,
      projetoCard: Color.lerp(projetoCard, other.projetoCard, t)!,
      projetoTxt: Color.lerp(projetoTxt, other.projetoTxt, t)!,
      fab: Color.lerp(fab, other.fab, t)!,
      fabIcone: Color.lerp(fabIcone, other.fabIcone, t)!,
      barraFerramentas: Color.lerp(barraFerramentas, other.barraFerramentas, t)!,
      neumorfico: neumorfico,
      fundoInicio: Color.lerp(fundoInicio, other.fundoInicio, t)!,
      fundoFim: Color.lerp(fundoFim, other.fundoFim, t)!,
      sombraForte: Color.lerp(sombraForte, other.sombraForte, t)!,
      sombraFraca: Color.lerp(sombraFraca, other.sombraFraca, t)!,
      brilho: Color.lerp(brilho, other.brilho, t)!,
      bordaLuz: Color.lerp(bordaLuz, other.bordaLuz, t)!,
      projetoCardFim: Color.lerp(projetoCardFim, other.projetoCardFim, t)!,
      barraFerramentasFim: Color.lerp(
          barraFerramentasFim, other.barraFerramentasFim, t)!,
      textoUI: Color.lerp(textoUI, other.textoUI, t)!,
    );
  }
}