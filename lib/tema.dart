import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tema do aplicativo.
enum Modo { claro, escuro, bege }

/// Controla o tema (claro/escuro/bege) do app e salva a escolha.
class TemaController extends ChangeNotifier {
  static const _chave = 'tema_v2';
  static const _chaveAntiga = 'tema_escuro_v1';
  Modo _modo = Modo.claro;

  Modo get modo => _modo;

  /// Modo usado pelo [MaterialApp] (bege é um tema claro).
  ThemeMode get themeFlutter =>
      _modo == Modo.escuro ? ThemeMode.dark : ThemeMode.light;

  /// Carrega a preferência salva (chamar no início do app).
  Future<void> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final antigo = prefs.getBool(_chaveAntiga);
    final salvo = prefs.getString(_chave) ??
        (antigo == true ? 'escuro' : 'claro');
    _modo = Modo.values
        .firstWhere((m) => m.name == salvo, orElse: () => Modo.claro);
    notifyListeners();
  }

  Future<void> definir(Modo modo) async {
    if (_modo == modo) return;
    _modo = modo;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chave, modo.name);
  }
}

/// Instância única usada pelo app.
final TemaController temaController = TemaController();