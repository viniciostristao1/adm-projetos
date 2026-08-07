import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controla o tema (claro/escuro) do app e salva a escolha.
class TemaController extends ChangeNotifier {
  static const _chave = 'tema_escuro_v1';
  ThemeMode _modo = ThemeMode.light;

  ThemeMode get modo => _modo;

  bool get escuro => _modo == ThemeMode.dark;

  /// Carrega a preferência salva (chamar no início do app).
  Future<void> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final escuro = prefs.getBool(_chave);
    _modo = (escuro ?? false) ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> definir({required bool escuro}) async {
    _modo = escuro ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chave, escuro);
  }
}

/// Instância única usada pelo app.
final TemaController temaController = TemaController();