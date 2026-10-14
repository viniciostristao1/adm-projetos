import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'chat_models.dart';

/// Histórico LOCAL das conversas do Muse. Chave PRÓPRIA no SharedPreferences —
/// NÃO toca no `Storage` dos projetos nem na cadeia de proteção do AGENTS.md.
class ChatStore {
  static const _chave = 'taskix_muse_convs_v1';
  static const _chaveAntiga = 'taskix_chat_v1'; // conversa única (pré-histórico)
  static const _chaveUltima = 'taskix_muse_ultima_v1'; // id da última conversa ativa
  static const _maxConversas = 60;
  static const _maxMsgs = 120; // por conversa

  /// Fila FIFO de gravações: `salvar`/`remover` encadeiam aqui para nunca haver
  /// dois read-modify-write concorrentes (o 2º lia antes do 1º gravar e o 1º,
  /// mais lento, sobrescrevia o mais novo = mensagens sumindo ao sair/voltar).
  static Future<void> _fila = Future.value();

  /// Espera a fila esvaziar (usado em testes).
  static Future<void> sincronizar() => _fila;

  /// Marca/ lê qual foi a última conversa aberta (para reabrir a MESMA ao voltar).
  static Future<void> marcarUltima(String id) async {
    try {
      (await SharedPreferences.getInstance()).setString(_chaveUltima, id);
    } catch (_) {}
  }

  static Future<String?> ultimaId() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_chaveUltima);
    } catch (_) {
      return null;
    }
  }

  /// Todas as conversas, mais recentes primeiro. Migra a conversa antiga (única)
  /// para uma Conversa na 1ª vez, para não perder o chat atual.
  static Future<List<Conversa>> listar() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_chave);
      if (s != null && s.isNotEmpty) {
        final list = (jsonDecode(s) as List)
            .map((e) => Conversa.fromJson(e as Map<String, dynamic>))
            .toList();
        list.sort((a, b) => b.atualizadaEm.compareTo(a.atualizadaEm));
        return list;
      }
      // migração do formato antigo
      final antiga = p.getString(_chaveAntiga);
      if (antiga != null && antiga.isNotEmpty) {
        final msgs = (jsonDecode(antiga) as List)
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        if (msgs.isNotEmpty) {
          final c = Conversa(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            titulo: 'Conversa anterior',
            preset: ChatPreset.projetos,
            mensagens: msgs,
            atualizadaEm: msgs.last.hora,
          )..talvezTitular();
          await _gravar([c]);
          await p.remove(_chaveAntiga);
          return [c];
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Insere/atualiza a conversa (upsert). Fotografa o estado NA HORA da chamada
  /// e aplica na fila, em ordem: o último estado fotografado sempre vence —
  /// sair da tela e voltar em segundos não perde mais mensagens.
  static Future<void> salvar(Conversa conv) {
    // Deep-copy via JSON para desgrudar do objeto vivo (que continua mutando
    // enquanto a fila anda); o corte de _maxMsgs vale só na cópia.
    final foto = Conversa.fromJson(conv.toJson());
    if (foto.mensagens.length > _maxMsgs) {
      foto.mensagens = foto.mensagens.sublist(foto.mensagens.length - _maxMsgs);
    }
    foto.atualizadaEm = DateTime.now();
    _fila = _fila.then((_) async {
      try {
        final todas = await listar();
        todas.removeWhere((c) => c.id == foto.id);
        todas.insert(0, foto);
        await _gravar(todas);
      } catch (_) {}
    });
    return _fila;
  }

  static Future<void> remover(String id) {
    _fila = _fila.then((_) async {
      try {
        final todas = await listar()
          ..removeWhere((c) => c.id == id);
        await _gravar(todas);
      } catch (_) {}
    });
    return _fila;
  }

  static Future<void> _gravar(List<Conversa> todas) async {
    final p = await SharedPreferences.getInstance();
    final corte = todas.length > _maxConversas
        ? todas.sublist(0, _maxConversas)
        : todas;
    await p.setString(
        _chave, jsonEncode(corte.map((c) => c.toJson()).toList()));
  }
}
