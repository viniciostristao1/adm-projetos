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
  /// Cópia de preservação do arquivo principal que estava ILEGÍVEL (gravada
  /// UMA vez, nunca sobrescrita) — para análise/reparo manual depois.
  static const _arquivoCorrompido = 'adm_projetos.corrompido.json';
  List<Projeto> _projetos = [];
  bool _carregado = false;
  int _atualizadoEm = 0;
  String? _dir;

  /// true quando o carregamento REPAROU um arquivo danificado (aviso na tela).
  bool _recuperadoDeCorrupcao = false;
  bool get recuperadoDeCorrupcao => _recuperadoDeCorrupcao;

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
      _projetos = _parseProjetos(dados) ?? [];
      _atualizadoEm = 0;
    } else if (dados is Map<String, dynamic>) {
      _projetos = _parseProjetos(dados['projetos']) ?? [];
      _atualizadoEm = (dados['atualizadoEm'] as int?) ?? 0;
    }
  }

  /// Converte a lista bruta em projetos, PULANDO os que estiverem inválidos —
  /// um projeto com dados estranhos não derruba a lista inteira.
  List<Projeto>? _parseProjetos(dynamic lista) {
    if (lista is! List) return null;
    final out = <Projeto>[];
    for (final e in lista) {
      try {
        out.add(Projeto.fromJson(e as Map<String, dynamic>));
      } catch (_) {
        debugPrint('storage: projeto inválido ignorado no carregamento');
      }
    }
    return out;
  }

  /// Tenta REPARAR um JSON danificado (ex.: gravação interrompida no meio).
  /// Estratégias, em ordem:
  /// 1. parse direto tolerante (um projeto inválido não derruba a lista);
  /// 2. corte progressivo: do fim para o início, corta em cada `}`/`]` e
  ///    devolve a MAIOR parte que ainda parseia (recupera tudo que foi
  ///    gravado antes do ponto da corrupção);
  /// 3. se o arquivo começa com lixo, tenta a partir do 1º `{`/`[`.
  bool _tentarSalvamento(String raw) {
    if (raw.trim().isEmpty) return false;

    List<Projeto>? tentar(Object? dados) {
      if (dados is List) return _parseProjetos(dados);
      if (dados is Map<String, dynamic>) {
        return _parseProjetos(dados['projetos']);
      }
      return null;
    }

    try {
      final p = tentar(jsonDecode(raw));
      if (p != null && p.isNotEmpty) {
        _projetos = p;
        _atualizadoEm = 0;
        return true;
      }
    } catch (_) {}

    final cortes = <int>[];
    for (var i = raw.length - 1; i >= 0 && cortes.length < 60; i--) {
      final c = raw[i];
      if (c == '}' || c == ']') cortes.add(i);
    }
    for (final idx in cortes) {
      // Corte no último `}`/`]` válido; o envelope `projetos` precisa ser
      // fechado de novo (ou o corte já caiu depois do fim real).
      for (final sufixo in const ['', ']}', ']', '}']) {
        try {
          final p = tentar(jsonDecode(raw.substring(0, idx + 1) + sufixo));
          if (p != null && p.isNotEmpty) {
            _projetos = p;
            _atualizadoEm = 0;
            debugPrint('storage: JSON reparado cortando em $idx (+"$sufixo")');
            return true;
          }
        } catch (_) {}
      }
    }

    final iniObj = raw.indexOf('{');
    final iniArr = raw.indexOf('[');
    final start = iniObj < 0
        ? iniArr
        : (iniArr < 0 ? iniObj : (iniObj < iniArr ? iniObj : iniArr));
    if (start > 0) {
      try {
        final p = tentar(jsonDecode(raw.substring(start)));
        if (p != null && p.isNotEmpty) {
          _projetos = p;
          _atualizadoEm = 0;
          debugPrint('storage: JSON reparado ignorando prefixo ($start)');
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  Future<List<Projeto>> carregar() async {
    if (_carregado) return _projetos;
    String? lerSeExiste(File f) {
      if (!f.existsSync()) return null;
      final conteudo = f.readAsStringSync();
      if (conteudo.trim().isEmpty) return null;
      return conteudo;
    }

    final dir = await _dirPath();
    var raw = lerSeExiste(File('$dir/$_arquivo'));
    if (raw != null) {
      try {
        _lerConteudo(raw);
      } catch (_) {
        // PRINCIPAL CORROMPIDO: preserva os bytes originais (1ª cópia) para
        // análise futura, tenta REPARAR o JSON e, se falhar, usa o .bak.
        debugPrint('storage: arquivo principal ilegível — tentando resgate');
        final corrompido = File('$dir/$_arquivoCorrompido');
        if (!corrompido.existsSync()) {
          try {
            corrompido.writeAsStringSync(raw);
          } catch (_) {}
        }
        _projetos = [];
        _atualizadoEm = 0;
        if (!_tentarSalvamento(raw)) {
          final bak = lerSeExiste(File('$dir/$_arquivoBak'));
          if (bak != null) {
            try {
              _lerConteudo(bak);
              debugPrint('storage: restaurado do backup após corrupção (.bak)');
            } catch (_) {
              _projetos = [];
              _atualizadoEm = 0;
            }
          }
        } else {
          _recuperadoDeCorrupcao = true;
          debugPrint('storage: DADOS REPARADOS (${_projetos.length} projetos)');
        }
      }
    } else {
      // Arquivo principal ausente/vazio: tenta o backup automático.
      final bak = lerSeExiste(File('$dir/$_arquivoBak'));
      if (bak != null) {
        try {
          _lerConteudo(bak);
          debugPrint('storage: dados restaurados do backup (.bak)');
        } catch (_) {
          _projetos = [];
          _atualizadoEm = 0;
        }
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

  /// Texto de diagnóstico dos arquivos de dados (tela de Configurações):
  /// tamanhos, se parseiam e quantos projetos cada um carrega — usado para
  /// investigar "apagou tudo" direto no aparelho.
  Future<String> diagnostico() async {
    final dir = await _dirPath();
    final buf = StringBuffer();

    Future<void> arquivo(String nome) async {
      final f = File('$dir/$nome');
      if (!f.existsSync()) {
        buf.writeln('$nome: AUSENTE');
        return;
      }
      final bytes = f.lengthSync();
      String parse;
      String extra = '';
      try {
        final conteudo = f.readAsStringSync();
        final dados = jsonDecode(conteudo);
        final n = _parseProjetos(
                dados is List ? dados : (dados as Map)['projetos'])
            ?.length;
        parse = 'OK';
        extra = ' projetos=$n';
        if (conteudo.length > 200) {
          extra += '\n    ini: ${conteudo.substring(0, 100)}'
              '\n    fim: ${conteudo.substring(conteudo.length - 100)}';
        }
      } catch (_) {
        parse = 'ILEGÍVEL';
        try {
          final conteudo = f.readAsStringSync();
          if (conteudo.length > 200) {
            extra = '\n    ini: ${conteudo.substring(0, 100)}'
                '\n    fim: ${conteudo.substring(conteudo.length - 100)}';
          }
        } catch (_) {}
      }
      buf.writeln('$nome: bytes=$bytes parse=$parse$extra');
    }

    buf.writeln('caminho: $dir');
    await arquivo(_arquivo);
    await arquivo(_arquivoBak);
    await arquivo(_arquivoCorrompido);
    return buf.toString();
  }
}
