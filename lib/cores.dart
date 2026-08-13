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

  /// Tema claro (botão "+" em azul claro, pastas azuis).
  static const AppCores luz = AppCores(
    notaInicio: Color(0xFFF6FAFF),
    notaFim: Color(0xFFEAF1FA),
    notaBorda: Color(0x1A0B1220),
    projetoCard: Color(0xFF1E3A8A),
    projetoTxt: Colors.white,
    fab: Color(0xFF4FC3F7),
    fabIcone: Color(0xFF0B2E44),
    barraFerramentas: Color(0xFF1E3A8A),
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

  /// Tema bege: fundo creme, cartões do projeto e o botão "+" em marrom.
  static const AppCores bege = AppCores(
    notaInicio: Color(0xFFFFF9F0),
    notaFim: Color(0xFFF1E9D7),
    notaBorda: Color(0x336D4C2F),
    projetoCard: Color(0xFF6D4C2F),
    projetoTxt: Color(0xFFFBF3E8),
    fab: Color(0xFF6D4C2F),
    fabIcone: Color(0xFFFBF3E8),
    barraFerramentas: Color(0xFF6D4C2F),
  );

  /// Tema A (Dark Neumorphism): grafite + âmbar.
  static const AppCores neumA = AppCores(
    notaInicio: Color(0xFF26292C),
    notaFim: Color(0xFF1B1E20),
    notaBorda: Color(0x00FFFFFF),
    projetoCard: Color(0xFF26292C),
    projetoTxt: Color(0xFFF2F4F5),
    fab: Color(0xFFE8A13A),
    fabIcone: Color(0xFF1A1309),
    barraFerramentas: Color(0xFF1B1E20),
    neumorfico: true,
    fundoInicio: Color(0xFF1C1F21),
    fundoFim: Color(0xFF121416),
  );

  /// Tema B (Dark Neumorphism): aço + gelo.
  static const AppCores neumB = AppCores(
    notaInicio: Color(0xFF232B34),
    notaFim: Color(0xFF181F27),
    notaBorda: Color(0x00FFFFFF),
    projetoCard: Color(0xFF232B34),
    projetoTxt: Color(0xFFEDF2F5),
    fab: Color(0xFF79B8DC),
    fabIcone: Color(0xFF0C141A),
    barraFerramentas: Color(0xFF181F27),
    neumorfico: true,
    fundoInicio: Color(0xFF181D24),
    fundoFim: Color(0xFF0E1115),
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
    );
  }
}