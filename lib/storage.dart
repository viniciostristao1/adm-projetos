import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Guarda os projetos num arquivo JSON no diretório de documentos do app.
///
/// Formato do arquivo (v2): `{"atualizadoEm": ms, "projetos": [...]}` —
/// dados e horário gravados JUNTOS, para o horário nunca ficar "mais novo"
/// que o conteúdo. Formato antigo (lista pura) é lido por compatibilidade.
///
/// Depois do primeiro carregamento (que resolve o diretório), os
/// salvamentos são SÍNCRONOS: quando `salvar()` retorna, o texto já está no
/// disco — nada se perde ao fechar o app logo em seguida.
class Storage extends ChangeNotifier {
  Storage._();
  static final Storage instance = Storage._();

  static const _arquivo = 'adm_projetos.json';
  List<Projeto> _projetos = [];
  bool _carregado = false;
  int _atualizadoEm = 0;
  String? _dir;

  Future<String> _dirPath() async {
    if (_dir == null) {
      final dir = await getApplicationDocumentsDirectory();
      _dir = dir.path;
    }
    return _dir!;
  }

  void _lerConteudo(String raw) {
    final dados = jsonDecode(raw);
    if (dados is List) {
      // formato antigo (lista pura)
      _projetos = dados
          .map((e) => Projeto.fromJson(e as Map<String, dynamic>))
          .toList();
      _atualizadoEm = 0;
    } else if (dados is Map<String, dynamic>) {
      _projetos = (dados['projetos'] as List)
          .map((e) => Projeto.fromJson(e as Map<String, dynamic>))
          .toList();
      _atualizadoEm = (dados['atualizadoEm'] as int?) ?? 0;
    }
  }

  Future<List<Projeto>> carregar() async {
    if (_carregado) return _projetos;
    try {
      final dir = await _dirPath();
      final f = File('$dir/$_arquivo');
      if (f.existsSync()) {
        _lerConteudo(f.readAsStringSync());
      }
    } catch (_) {
      _projetos = [];
      _atualizadoEm = 0;
    }
    _carregado = true;
    return _projetos;
  }

  /// Grava dados + horário JUNTOS no disco. No fluxo normal (após o primeiro
  /// carregamento) o corpo roda 100% síncrono: ao retornar, já está no disco.
  Future<void> salvar() async {
    if (!_carregado) await carregar(); // raro: salvar antes do 1º carregar
    _atualizadoEm = DateTime.now().millisecondsSinceEpoch;
    final conteudo = jsonEncode({
      'atualizadoEm': _atualizadoEm,
      'projetos': _projetos.map((p) => p.toJson()).toList(),
    });
    notifyListeners();
    try {
      final dir = _dir;
      if (dir != null) {
        File('$dir/$_arquivo').writeAsStringSync(conteudo);
      }
    } catch (e) {
      debugPrint('storage: falha ao salvar: $e');
    }
  }

  /// Horário (ms) da última modificação — vem do PRÓPRIO arquivo (sempre
  /// consistente com o conteúdo, nunca mais novo que ele).
  Future<int> ultimaModificacaoMs() async {
    await carregar();
    return _atualizadoEm;
  }

  /// Define o horário da última modificação (quando os dados vêm da nuvem) e
  /// regrava o arquivo para manter dados + horário consistentes. NUNCA volta
  /// o relógio do arquivo: se o horário atual já é mais novo (ex.: uma tecla
  /// salvou durante a sincronização), mantém o atual.
  Future<void> marcarModificacaoEm(int ms) async {
    if (ms <= _atualizadoEm) return;
    _atualizadoEm = ms;
    final conteudo = jsonEncode({
      'atualizadoEm': ms,
      'projetos': _projetos.map((p) => p.toJson()).toList(),
    });
    try {
      final dir = _dir;
      if (dir != null) {
        File('$dir/$_arquivo').writeAsStringSync(conteudo);
      }
    } catch (e) {
      debugPrint('storage: falha ao marcar modificação: $e');
    }
  }

  /// JSON cru de todos os projetos (para exportar em arquivo de backup e
  /// para enviar à nuvem) — lista pura, compatível com backups antigos.
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
