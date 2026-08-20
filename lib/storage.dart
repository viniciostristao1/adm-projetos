import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  /// Backup automático: guarda a versão ANTERIOR do arquivo a cada gravação;
  /// o `carregar()` restaura dele se o principal sumir ou corromper.
  static const _arquivoBak = 'adm_projetos.bak.json';
  List<Projeto> _projetos = [];
  bool _carregado = false;
  int _atualizadoEm = 0;
  String? _dir;

  /// Só para testes: zera o estado do singleton (diretório, flag e dados).
  @visibleForTesting
  void reiniciarParaTeste() {
    _carregado = false;
    _projetos = [];
    _atualizadoEm = 0;
    _dir = null;
  }

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
    String? lerSeExiste(File f) {
      if (!f.existsSync()) return null;
      final conteudo = f.readAsStringSync();
      if (conteudo.trim().isEmpty) return null;
      return conteudo;
    }

    try {
      final dir = await _dirPath();
      var raw = lerSeExiste(File('$dir/$_arquivo'));
      if (raw == null) {
        // Arquivo principal ausente/vazio: tenta o backup automático.
        raw = lerSeExiste(File('$dir/$_arquivoBak'));
        if (raw != null) {
          debugPrint('storage: dados restaurados do backup (.bak)');
        }
      }
      if (raw != null) _lerConteudo(raw);
    } catch (_) {
      // Principal corrompido: tenta o backup automático.
      _projetos = [];
      _atualizadoEm = 0;
      try {
        final dir = await _dirPath();
        final bak = File('$dir/$_arquivoBak');
        if (bak.existsSync()) {
          _lerConteudo(bak.readAsStringSync());
          debugPrint('storage: restaurado do backup após corrupção (.bak)');
        }
      } catch (_) {
        _projetos = [];
        _atualizadoEm = 0;
      }
    }
    _carregado = true;
    return _projetos;
  }

  /// Grava no arquivo principal, ANTES guardando a versão anterior no `.bak`
  /// (só quando o conteúdo muda) — proteção contra escrita corrompida ou
  /// sobrescrita acidental.
  void _gravar(String conteudo) {
    final dir = _dir;
    if (dir == null) return;
    final f = File('$dir/$_arquivo');
    final bak = File('$dir/$_arquivoBak');
    if (f.existsSync()) {
      try {
        final anterior = f.readAsStringSync();
        if (anterior != conteudo) bak.writeAsStringSync(anterior);
      } catch (_) {}
    }
    f.writeAsStringSync(conteudo);
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
      _gravar(conteudo);
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
      _gravar(conteudo);
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

  /// Quantos projetos a prateleira "Recentes" mostra.
  static const int maxRecentes = 5;
  static const _chaveRecentes = 'recentes_v1';

  /// IDs dos projetos mais recentemente abertos (primeiro = mais recente).
  Future<List<String>> recentesIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_chaveRecentes) ?? [];
  }

  /// Move o projeto para o topo da lista de recentes (máx. [maxRecentes]).
  Future<void> registrarAbertura(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final lista = prefs.getStringList(_chaveRecentes) ?? [];
    lista.remove(id);
    lista.insert(0, id);
    await prefs.setStringList(
        _chaveRecentes, lista.take(maxRecentes).toList());
  }

  /// Remove o projeto dos recentes (usado ao excluir a pasta).
  Future<void> removerRecente(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final lista = prefs.getStringList(_chaveRecentes) ?? [];
    lista.remove(id);
    await prefs.setStringList(_chaveRecentes, lista);
  }
}
