import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'chat_models.dart';

/// Persistência LOCAL da conversa atual. Usa chave PRÓPRIA no SharedPreferences —
/// NÃO toca no `Storage` dos projetos nem na cadeia de proteção do AGENTS.md.
/// (Histórico de várias conversas fica para a Fase 2.)
class ChatStore {
  static const _chave = 'taskix_chat_v1';
  static const _max = 60; // guarda só as últimas N mensagens

  static Future<List<ChatMessage>> carregar() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_chave);
      if (s == null || s.isEmpty) return [];
      final list = jsonDecode(s) as List;
      return list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> salvar(List<ChatMessage> msgs) async {
    try {
      final p = await SharedPreferences.getInstance();
      final corte = msgs.length > _max ? msgs.sublist(msgs.length - _max) : msgs;
      await p.setString(
          _chave, jsonEncode(corte.map((m) => m.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> limpar() async {
    try {
      (await SharedPreferences.getInstance()).remove(_chave);
    } catch (_) {}
  }
}
