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

  /// Tema Bege (estilo Calis Timer — madeira): tons amadeirados claros
  /// (bege/madeira) com accent laranja-marrom. Plano, sem relevo neumórfico.
  /// FUNDO da página principal em bege CLARO; pastas/caixinhas em bege
  /// escuro (#E0D1B9).
  static const AppCores bege = AppCores(
    notaInicio: Color(0xFFE0D1B9),
    notaFim: Color(0xFFCBB897),
    notaBorda: Color(0x14000000),
    projetoCard: Color(0xFFE0D1B9),
    projetoCardFim: Color(0xFFD8C7AC),
    projetoTxt: Color(0xFF382E20),
    fab: Color(0xFFB5652E),
    fabIcone: Color(0xFFFFF3E7),
    barraFerramentas: Color(0xFFCBB897),
    barraFerramentasFim: Color(0xFFCBB897),
    fundoInicio: Color(0xFFF2E8D6),
    fundoFim: Color(0xFFEADFC8),
    textoUI: Color(0xFF382E20),
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