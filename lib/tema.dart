import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tema do aplicativo.
enum Modo {
  azul('Azul'),
  escuro('Escuro'),
  neumB('Dark Game'),
  bege('Bege'),
  claude('Terracota'),
  onix('Ônix');

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

/// Densidade da interface: Confortável (atual) ou Compacto (linhas e cartões
/// mais próximos, mais conteúdo por tela).
enum Densidade {
  confortavel('Confortável'),
  compacto('Compacto');

  const Densidade(this.rotulo);
  final String rotulo;
}

/// Controla o tema (claro/escuro/bege), tamanho da fonte e densidade,
/// salvando as escolhas.
class TemaController extends ChangeNotifier {
  static const _chave = 'tema_v2';
  static const _chaveAntiga = 'tema_escuro_v1';
  static const _chaveFonte = 'fonte_v1';
  static const _chaveDensidade = 'densidade_v1';
  // Cores que marcam as seções FOCO (topo) e PRÓXIMOS (abaixo de EM ANDAMENTO)
  // na tela inicial, pelas cores do cantinho da pasta. Padrão: foco=amarelo,
  // próximos=verde. `_chaveCorAbertoAntiga` migra o nome anterior ("em aberto",
  // V0.1.92/93) para PRÓXIMOS.
  static const _chaveCorFoco = 'cor_foco_v1';
  static const _chaveCorProximos = 'cor_proximos_v1';
  static const _chaveCorAbertoAntiga = 'cor_em_aberto_v1';
  Modo _modo = Modo.azul;
  ModoFonte _fonte = ModoFonte.normal;
  Densidade _densidade = Densidade.confortavel;
  String? _corFoco;
  String? _corProximos;

  Modo get modo => _modo;
  ModoFonte get fonte => _fonte;
  Densidade get densidade => _densidade;

  /// Nome da cor (em `mapaCoresPasta`) que marca a seção FOCO; null = desligado.
  String? get corFoco => _corFoco;

  /// Nome da cor que marca a seção PRÓXIMOS; null = desligado.
  String? get corProximos => _corProximos;

  /// true no modo Compacto (linhas/cartões mais próximos).
  bool get compacto => _densidade == Densidade.compacto;

  /// Modo usado pelo [MaterialApp] — Bege é claro (madeira do Calis Timer);
  /// os demais são escuros.
  ThemeMode get themeFlutter =>
      _modo == Modo.bege ? ThemeMode.light : ThemeMode.dark;

  /// Carrega as preferências salvas (chamar no início do app). Temas antigos
  /// removidos migram para os novos: claro → azul, espresso → bege,
  /// bege/begeNeum → bege.
  Future<void> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final antigo = prefs.getBool(_chaveAntiga);
    final salvo = prefs.getString(_chave) ??
        (antigo == true ? 'escuro' : 'azul');
    final migrado = switch (salvo) {
      'claro' => 'azul',
      'espresso' || 'bege' || 'begeNeum' => 'bege',
      _ => salvo,
    };
    _modo = Modo.values
        .firstWhere((m) => m.name == migrado, orElse: () => Modo.azul);
    final fonteSalva = prefs.getString(_chaveFonte);
    _fonte = ModoFonte.values
        .firstWhere((f) => f.name == fonteSalva, orElse: () => ModoFonte.normal);
    final densidadeSalva = prefs.getString(_chaveDensidade);
    _densidade = Densidade.values
        .firstWhere((d) => d.name == densidadeSalva,
            orElse: () => Densidade.confortavel);
    // Defaults LIGADOS: foco=amarelo, próximos=verde (migra o antigo "em
    // aberto" para próximos se existir). Uma string vazia salva = "nenhuma".
    _corFoco = _lerCorPref(prefs, _chaveCorFoco, 'amarelo');
    _corProximos = _lerCorPref(
        prefs, _chaveCorProximos, 'verde',
        chaveFallback: _chaveCorAbertoAntiga);
    notifyListeners();
  }

  /// Lê uma cor de seção: ausente → [padrao]; string vazia → null (desligado);
  /// senão o valor salvo. [chaveFallback] cobre a migração de nome.
  String? _lerCorPref(SharedPreferences prefs, String chave, String padrao,
      {String? chaveFallback}) {
    var v = prefs.getString(chave);
    v ??= chaveFallback == null ? null : prefs.getString(chaveFallback);
    if (v == null) return padrao; // nunca configurado → default ligado
    return v.isEmpty ? null : v; // "" = nenhuma (desligado explicitamente)
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

  Future<void> definirDensidade(Densidade densidade) async {
    if (_densidade == densidade) return;
    _densidade = densidade;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveDensidade, densidade.name);
  }

  /// Define (null = nenhuma) a cor da seção FOCO. Se colidir com a de PRÓXIMOS,
  /// limpa a de PRÓXIMOS (uma cor nunca pode significar dois grupos).
  Future<void> definirCorFoco(String? cor) async {
    if (_corFoco == cor) return;
    _corFoco = cor;
    if (cor != null && _corProximos == cor) _corProximos = null;
    notifyListeners();
    await _salvarCoresSecao();
  }

  /// Define (null = nenhuma) a cor da seção PRÓXIMOS. Se colidir com FOCO,
  /// limpa a de FOCO.
  Future<void> definirCorProximos(String? cor) async {
    if (_corProximos == cor) return;
    _corProximos = cor;
    if (cor != null && _corFoco == cor) _corFoco = null;
    notifyListeners();
    await _salvarCoresSecao();
  }

  // Grava as duas cores. null vira "" (configurado como "nenhuma"), para o
  // carregar() distinguir "desligado de propósito" de "nunca configurado".
  Future<void> _salvarCoresSecao() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveCorFoco, _corFoco ?? '');
    await prefs.setString(_chaveCorProximos, _corProximos ?? '');
  }
}

/// Instância única usada pelo app.
final TemaController temaController = TemaController();