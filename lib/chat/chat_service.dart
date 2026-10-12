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
/// Resultado de um vídeo do YouTube (transcrição ou resumo).
class YoutubeResult {
  final String? titulo;
  final String? texto;
  final String? erro;
  const YoutubeResult.ok(this.titulo, this.texto) : erro = null;
  const YoutubeResult.falha(this.erro)
      : titulo = null,
        texto = null;
  bool get sucesso => texto != null;
}

class ChatService {
  /// Transcreve ou resume um vídeo do YouTube (pelo link), via proxy na VPS.
  static Future<YoutubeResult> youtube(
      String url, String modo, String modeloId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const YoutubeResult.falha('Entre na sua conta Google para usar.');
    }
    String token;
    try {
      token = (await user.getIdToken()) ?? '';
    } catch (_) {
      return const YoutubeResult.falha('Login inválido. Saia e entre de novo.');
    }
    try {
      final r = await http
          .post(
            Uri.parse('${ChatConfig.url}/youtube'),
            headers: {
              'content-type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'url': url, 'modo': modo, 'model': modeloId}),
          )
          .timeout(const Duration(seconds: 170));
      if (r.statusCode == 200) {
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        return YoutubeResult.ok(
            j['titulo'] as String?, (j['texto'] as String?)?.trim());
      }
      return YoutubeResult.falha(switch (r.statusCode) {
        400 => 'Link do YouTube inválido.',
        422 => 'Esse vídeo não tem legendas disponíveis.',
        401 => 'Seu login expirou. Saia e entre de novo.',
        403 => 'Esta conta não tem acesso.',
        _ => 'Erro ${r.statusCode}. Tente de novo.',
      });
    } catch (_) {
      return const YoutubeResult.falha(
          'Sem resposta (rede ou tempo). Tente de novo.');
    }
  }

  /// Envia o histórico com o preset (modo) e o modelo escolhidos.
  static Future<ChatResult> enviar(
    List<ChatMessage> historico, {
    required String presetId,
    required String modeloId,
    String? imagemB64,
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
            body: jsonEncode({
              'messages': msgs,
              'preset': presetId,
              'model': modeloId,
              'imagem_b64': ?imagemB64,
            }),
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
