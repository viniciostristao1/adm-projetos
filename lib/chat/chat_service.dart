import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'chat_config.dart';
import 'chat_models.dart';

/// Resultado de um envio: ou a resposta da IA, ou uma mensagem de erro amigável.
class ChatResult {
  final String? reply;
  final String? erro;
  const ChatResult.ok(this.reply) : erro = null;
  const ChatResult.falha(this.erro) : reply = null;
  bool get sucesso => reply != null;
}

/// Cliente do proxy de chat na VPS. A chave do OpenCode Go vive SÓ no servidor;
/// aqui só vai o ID token do Firebase do usuário logado (o servidor só aceita a
/// conta do dono). Ver `AGENTS.md` (módulo de chat) e o proxy `/opt/taskix-chat`.
class ChatService {
  /// Envia o histórico com o preset (modo) e o modelo escolhidos.
  static Future<ChatResult> enviar(
    List<ChatMessage> historico, {
    required String presetId,
    required String modeloId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const ChatResult.falha(
          'Entre na sua conta Google (Config → nuvem) para usar o chat.');
    }
    String token;
    try {
      token = (await user.getIdToken()) ?? '';
    } catch (_) {
      return const ChatResult.falha(
          'Não consegui validar seu login. Saia e entre de novo.');
    }
    if (token.isEmpty) {
      return const ChatResult.falha('Login inválido. Saia e entre de novo.');
    }

    final msgs = historico
        .map((m) => {'role': m.role, 'content': m.texto})
        .toList(growable: false);
    try {
      final r = await http
          .post(
            Uri.parse('${ChatConfig.url}/chat'),
            headers: {
              'content-type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(
                {'messages': msgs, 'preset': presetId, 'model': modeloId}),
          )
          .timeout(const Duration(seconds: 170));

      if (r.statusCode == 200) {
        final reply =
            (jsonDecode(utf8.decode(r.bodyBytes))['reply'] as String?)?.trim();
        if (reply != null && reply.isNotEmpty) return ChatResult.ok(reply);
        return const ChatResult.falha('A IA não respondeu. Tente de novo.');
      }
      return ChatResult.falha(switch (r.statusCode) {
        401 => 'Seu login expirou. Saia e entre de novo.',
        403 => 'Esta conta não tem acesso ao chat.',
        502 => 'A IA está indisponível agora. Tente em instantes.',
        _ => 'Erro ${r.statusCode}. Tente de novo.',
      });
    } catch (_) {
      return const ChatResult.falha(
          'Sem resposta (rede ou tempo esgotado). Tente de novo.');
    }
  }
}
