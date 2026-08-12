import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Guarda os projetos num arquivo JSON no diretório de documentos do app.
class Storage {
  Storage._();
  static final Storage instance = Storage._();

  static const _arquivo = 'adm_projetos.json';
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
  }

  /// JSON cru de todos os projetos (para exportar em arquivo de backup).
  Future<String> exportarJson() async {
    await carregar();
    return jsonEncode(_projetos.map((p) => p.toJson()).toList());
  }

  /// Substitui os projetos por uma lista (importada de backup) e salva.
  Future<void> substituir(List<Projeto> projetos) async {
    await carregar();
    _projetos = List.of(projetos);
    await salvar();
  }
}