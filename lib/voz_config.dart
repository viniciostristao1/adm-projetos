import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Voz da Muse: velocidade e voz, com persistência.
///
/// - `velocidade` é o `lengthScale` do Piper/sherpa (MAIOR = fala mais
///   DEVAGAR; 1.04 = padrão aprovado pelo usuário).
/// - `vozId` 'dii' = feminina (sai NO APARELHO, offline, preferida);
///   'faber' = masculina (só existe no SERVIDOR — sem modelo faber no aparelho).
class VozController extends ChangeNotifier {
  static const chaveVelocidade = 'voz_velocidade_v1';
  static const chaveVoz = 'voz_id_v1';

  static const double velocidadePadrao = 1.04;
  static const double velocidadeMin = 0.85;
  static const double velocidadeMax = 1.25;
  static const String vozPadrao = 'dii';
  static const Set<String> vozesOk = {'dii', 'faber'};

  /// Quanto o "devagar" da conversa soma ao lengthScale.
  static const double devagarDelta = 0.16;

  double _velocidade = velocidadePadrao;
  String _vozId = vozPadrao;

  double get velocidade => _velocidade;
  String get vozId => _vozId;
  bool get masculina => _vozId == 'faber';
  String get rotuloVelocidade => '${_velocidade.toStringAsFixed(2)}×';
  String get rotuloVoz => masculina ? 'Masculina' : 'Feminina';

  /// Carrega as preferências salvas (chamar no início do app). Valor fora da
  /// faixa ou voz desconhecida caem no padrão.
  Future<void> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getDouble(chaveVelocidade);
    if (v != null && v.isFinite) {
      _velocidade = v.clamp(velocidadeMin, velocidadeMax).toDouble();
    }
    final id = prefs.getString(chaveVoz);
    if (id != null && vozesOk.contains(id)) _vozId = id;
    notifyListeners();
  }

  Future<void> definirVelocidade(double v) async {
    if (!v.isFinite) return;
    final c = v.clamp(velocidadeMin, velocidadeMax).toDouble();
    if (c == _velocidade) return;
    _velocidade = c;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(chaveVelocidade, c);
  }

  Future<void> definirVoz(String id) async {
    if (!vozesOk.contains(id) || id == _vozId) return;
    _vozId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(chaveVoz, id);
  }
}

/// Instância única usada pelo app.
final VozController vozController = VozController();
