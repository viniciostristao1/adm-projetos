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
  Future<void> _fila = Future.value();

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

  /// Salva os projetos em disco. As gravações são ENFILEIRADAS em ordem:
  /// cada chamada captura o estado ATUAL da lista na hora e grava por último
  /// quem foi chamado por último — sem corrida de gravações fora de ordem
  /// (que deixava o arquivo com texto pela metade).
  Future<void> salvar() {
    final conteudo =
        jsonEncode(_projetos.map((p) => p.toJson()).toList());
    notifyListeners();
    _fila = _fila.then((_) async {
      try {
        final f = await _file();
        await f.writeAsString(conteudo);
        await _marcarModificacao();
      } catch (e) {
        debugPrint('storage: falha ao salvar: $e');
      }
    });
    return _fila;
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
