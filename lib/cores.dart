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

  /// Tema escuro: fundo cinza escuro, pastas bem pretas, FAB âmbar.
  static const AppCores escuro = AppCores(
    notaInicio: Color(0xFF242424),
    notaFim: Color(0xFF242424),
    notaBorda: Color(0x33FFFFFF),
    projetoCard: Colors.black,
    projetoTxt: Color(0xFFE0E0E0),
    fab: Color(0xFFF0A500),
    fabIcone: Color(0xFF1A1200),
    barraFerramentas: Colors.black,
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
    );
  }
}