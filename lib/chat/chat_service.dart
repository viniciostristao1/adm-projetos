import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'chat_config.dart';
import 'chat_models.dart';
import 'chat_store.dart';

/// Resultado de um envio: ou a resposta da IA, ou uma mensagem de erro amigável.
class ChatResult {
  final String? reply;
  final String? erro;
  const ChatResult.ok(this.reply) : erro = null;
  const ChatResult.falha(this.erro) : reply = null;
  bool get sucesso => reply != null;
}

/// Evento do envio em STREAMING (frase a frase).
/// tipo: 'frase' (uma frase pronta) | 'done' (fim; `texto` = resposta inteira,
/// JÁ salva no store) | 'erro' (falhou; `texto` = motivo).
class MuseEvent {
  final String tipo;
  final String texto;
  final bool fimParagrafo; // só em 'frase': esta frase fecha um parágrafo
  const MuseEvent(this.tipo, this.texto, {this.fimParagrafo = false});
}

/// Cliente do proxy de chat na VPS. A chave do OpenCode Go vive SÓ no servidor;
/// aqui só vai o ID token do Firebase do usuário logado (o servidor só aceita a
/// conta do dono). Ver `AGENTS.md` (módulo de chat) e o proxy `/opt/taskix-chat`.
class ChatService {
  /// Voz neural da VPS (MP3 pt-BR, voz feminina). Devolve os bytes do áudio ou
  /// null em qualquer falha (o chamador cai para o TTS local do aparelho).
  static Future<Uint8List?> audioNeural(String texto) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    String token;
    try {
      token = (await user.getIdToken()) ?? '';
    } catch (_) {
      return null;
    }
    if (token.isEmpty) return null;
    try {
      final r = await http
          .post(
            Uri.parse('${ChatConfig.url}/tts'),
            headers: {
              'content-type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'texto': texto}),
          )
          .timeout(const Duration(seconds: 60));
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) return r.bodyBytes;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Envios EM VOO, um por conversa: o futuro fica registrado até concluir
  /// (chamadas repetidas p/ a mesma conversa retornam o MESMO futuro — sem
  /// disparo duplo). É o que faz a resposta SOBREVIVER ao botão voltar: a tela
  /// pode ser destruída que o envio continua; ao concluir com sucesso, a
  /// resposta é anexada no store (fila) — a tela, se ainda montada, recarrega
  /// de lá; se saiu, a resposta espera salva e a tela reanexa ao voltar.
  static final Map<String, Future<ChatResult>> _voando = {};

  /// Futuro em voo p/ a conversa (ou null). A tela usa p/ reanexar ao voltar.
  static Future<ChatResult>? pendenteDe(String conversaId) =>
      _voando[conversaId];

  /// Envia com sobrevivência: registra em `_voando` e grava a resposta no
  /// store ao concluir. `historico` é fotografado na chamada (o chamador passa
  /// uma cópia — a lista viva da tela continua mutando).
  static Future<ChatResult> enviarNaConversa(
    String conversaId,
    List<ChatMessage> historico, {
    required String presetId,
    required String modeloId,
    String tamanhoId = 'longo',
    List<String>? imagensB64, // até 3 imagens (visão) p/ a última mensagem
  }) {
    final exist = _voando[conversaId];
    if (exist != null) return exist;
    final fut = enviar(historico,
            presetId: presetId,
            modeloId: modeloId,
            tamanhoId: tamanhoId,
            imagensB64: imagensB64)
        .then((res) async {
      _voando.remove(conversaId);
      if (res.sucesso) await ChatStore.anexarIa(conversaId, res.reply!);
      return res;
    });
    _voando[conversaId] = fut;
    return fut;
  }

  // ───────────────────────── Envio em STREAMING ─────────────────────────
  // Igual ao `_voando`, mas por STREAM: a consumição roda AQUI (no serviço), não
  // na tela — sobrevive ao botão voltar. Ao terminar, salva a resposta no store
  // (`anexarIa`, o MESMO caminho robusto do envio normal). A tela só escuta.
  static final Map<String, StreamController<MuseEvent>> _stream = {};

  /// Stream em voo p/ a conversa (ou null) — a tela usa p/ reatar ao voltar.
  static Stream<MuseEvent>? streamPendente(String conversaId) =>
      _stream[conversaId]?.stream;

  /// Envia em streaming; devolve um Stream (broadcast) de [MuseEvent]. Chamadas
  /// repetidas p/ a mesma conversa retornam o MESMO stream (sem disparo duplo).
  static Stream<MuseEvent> enviarStream(
    String conversaId,
    List<ChatMessage> historico, {
    required String presetId,
    required String modeloId,
    String tamanhoId = 'longo',
    List<String>? imagensB64,
  }) {
    final exist = _stream[conversaId];
    if (exist != null) return exist.stream;
    final ctrl = StreamController<MuseEvent>.broadcast();
    _stream[conversaId] = ctrl;
    _rodar(conversaId, historico, presetId, modeloId, tamanhoId, imagensB64, ctrl);
    return ctrl.stream;
  }

  static Future<void> _rodar(
    String id,
    List<ChatMessage> historico,
    String presetId,
    String modeloId,
    String tamanhoId,
    List<String>? imagensB64,
    StreamController<MuseEvent> ctrl,
  ) async {
    void emit(MuseEvent e) {
      if (!ctrl.isClosed) ctrl.add(e);
    }

    final full = StringBuffer();
    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = user == null ? '' : (await user.getIdToken() ?? '');
      if (token.isEmpty) {
        emit(const MuseEvent('erro', 'login'));
        return;
      }
      final msgs = historico
          .map((m) => {
                'role': m.role,
                'content': m.texto,
                'hora': m.hora.millisecondsSinceEpoch,
              })
          .toList(growable: false);
      final req = http.Request('POST', Uri.parse('${ChatConfig.url}/chat_stream'))
        ..headers['content-type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer $token'
        ..body = jsonEncode({
          'messages': msgs,
          'preset': presetId,
          'model': modeloId,
          'tamanho': tamanhoId,
          'imagens_b64': ?imagensB64,
        });
      final resp =
          await http.Client().send(req).timeout(const Duration(seconds: 190));
      if (resp.statusCode != 200) {
        emit(MuseEvent('erro', 'HTTP ${resp.statusCode}'));
        return;
      }
      String? replyFinal;
      await for (final line in resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty) continue;
        Map<String, dynamic> obj;
        try {
          obj = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        if (obj['erro'] != null) {
          emit(MuseEvent('erro', obj['erro'].toString()));
        } else if (obj['done'] == true) {
          replyFinal = (obj['reply'] as String?)?.trim();
        } else if (obj['t'] != null) {
          final f = obj['t'].toString().trim();
          if (f.isEmpty) continue;
          if (full.isNotEmpty) full.write(' ');
          full.write(f);
          emit(MuseEvent('frase', f, fimParagrafo: obj['p'] == true));
        }
      }
      final reply = (replyFinal != null && replyFinal.isNotEmpty)
          ? replyFinal
          : full.toString().trim();
      if (reply.isNotEmpty) {
        await ChatStore.anexarIa(id, reply); // mesmo save do envio normal
        emit(MuseEvent('done', reply));
      } else {
        emit(const MuseEvent('erro', 'vazio'));
      }
    } catch (_) {
      // Caiu no meio: salva o PARCIAL p/ não perder o que já veio.
      final parcial = full.toString().trim();
      if (parcial.isNotEmpty) {
        await ChatStore.anexarIa(id, parcial);
        emit(MuseEvent('done', parcial));
      } else {
        emit(const MuseEvent('erro', 'rede'));
      }
    } finally {
      _stream.remove(id);
      await ctrl.close();
    }
  }

  /// Envia o histórico com o preset (modo) e o modelo escolhidos.
  static Future<ChatResult> enviar(
    List<ChatMessage> historico, {
    required String presetId,
    required String modeloId,
    String tamanhoId = 'longo',
    List<String>? imagensB64, // até 3 imagens (visão) p/ a última mensagem
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
        .map((m) => {
              'role': m.role,
              'content': m.texto,
              'hora': m.hora.millisecondsSinceEpoch,
            })
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
              'tamanho': tamanhoId,
              'imagens_b64': ?imagensB64,
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
