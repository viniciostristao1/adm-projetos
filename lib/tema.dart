import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tema do aplicativo.
enum Modo {
  claro('Claro'),
  escuro('Escuro'),
  bege('Bege'),
  neumB('Dark Game'),
  begeNeum('Bege Game');

  const Modo(this.rotulo);
  final String rotulo;
}

/// Tamanho da fonte e dos ícones.
enum ModoFonte {
  pequeno('Pequena', 0.85),
  normal('Normal', 1.0),
  grande('Grande', 1.15),
  extraGrande('Extra grande', 1.3);

  const ModoFonte(this.rotulo, this.scale);
  final String rotulo;
  final double scale;
}

/// Controla o tema (claro/escuro/bege) e tamanho da fonte, salvando as escolhas.
class TemaController extends ChangeNotifier {
  static const _chave = 'tema_v2';
  static const _chaveAntiga = 'tema_escuro_v1';
  static const _chaveFonte = 'fonte_v1';
  Modo _modo = Modo.claro;
  ModoFonte _fonte = ModoFonte.normal;

  Modo get modo => _modo;
  ModoFonte get fonte => _fonte;

  /// Modo usado pelo [MaterialApp] (Dark Game é escuro; bege é claro).
  ThemeMode get themeFlutter =>
      _modo == Modo.escuro || _modo == Modo.neumB
          ? ThemeMode.dark
          : ThemeMode.light;

  /// Carrega as preferências salvas (chamar no início do app).
  Future<void> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final antigo = prefs.getBool(_chaveAntiga);
    final salvo = prefs.getString(_chave) ??
        (antigo == true ? 'escuro' : 'claro');
    _modo = Modo.values
        .firstWhere((m) => m.name == salvo, orElse: () => Modo.claro);
    final fonteSalva = prefs.getString(_chaveFonte);
    _fonte = ModoFonte.values
        .firstWhere((f) => f.name == fonteSalva, orElse: () => ModoFonte.normal);
    notifyListeners();
  }

  Future<void> definir(Modo modo) async {
    if (_modo == modo) return;
    _modo = modo;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chave, modo.name);
  }

  Future<void> definirFonte(ModoFonte fonte) async {
    if (_fonte == fonte) return;
    _fonte = fonte;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveFonte, fonte.name);
  }
}

/// Instância única usada pelo app.
final TemaController temaController = TemaController();