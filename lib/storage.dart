import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Guarda os projetos num arquivo JSON no diretório de documentos do app.
/// Também controla o horário da última modificação (para a sincronização com
/// a nuvem decidir quem tem os dados mais novos) e avisa os ouvintes quando
/// algo é salvo.
class Storage extends ChangeNotifier {
  Storage._();
  static final Storage instance = Storage._();

  static const _arquivo = 'adm_projetos.json';
  static const _chaveMod = 'ultima_modificacao_ms';
  List<Projeto> _projetos = [];
  bool _carregado = false;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_arquivo');
  }

  Future<List<Projeto>> carregar() async {
    if (_carregado) return _projetos;
    try {
      final f = await _file();
      if (await f.exists()) {
        final dados = jsonDecode(await f.readAsString()) as List;
        _projetos = dados
            .map((e) => Projeto.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      _projetos = [];
    }
    _carregado = true;
    return _projetos;
  }

  Future<void> salvar() async {
    final f = await _file();
    await f.writeAsString(jsonEncode(_projetos.map((p) => p.toJson()).toList()));
    await _marcarModificacao();
    notifyListeners();
  }

  Future<void> _marcarModificacao() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_chaveMod, DateTime.now().millisecondsSinceEpoch);
  }

  /// Horário (ms) da última modificação local.
  Future<int> ultimaModificacaoMs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_chaveMod) ?? 0;
  }

  /// Define o horário da última modificação sem salvar o arquivo (usado
  /// quando os dados vieram da nuvem e devem contar como "atuais").
  Future<void> marcarModificacaoEm(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_chaveMod, ms);
  }

  /// JSON cru de todos os projetos (para exportar em arquivo de backup e
  /// para enviar à nuvem).
  Future<String> exportarJson() async {
    await carregar();
    return jsonEncode(_projetos.map((p) => p.toJson()).toList());
  }

  /// Substitui os projetos por uma lista (importada de backup ou vinda da
  /// nuvem) e salva.
  Future<void> substituir(List<Projeto> projetos) async {
    await carregar();
    _projetos = List.of(projetos);
    await salvar();
  }
}
