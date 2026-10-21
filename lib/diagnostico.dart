import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'chat/chat_config.dart';
import 'versao.dart';

/// Captura de FALHAS do app (erros não-tratados + falhas registradas à mão) num
/// buffer local pequeno, para o usuário poder ENVIAR/COMPARTILHAR um relatório
/// quando algo trava — e assim o desenvolvedor ver o que ocorreu.
///
/// NÃO captura "ANR" (travamento da UI não é uma exceção Dart); para isso a cura
/// é não bloquear a thread (ver `tts_ondevice.dart`). Captura exceções, erros de
/// rede do Muse, e tudo que chegar aos handlers globais instalados no `main()`.
class Diagnostico {
  static const _chave = 'taskix_diag_v1';
  static const _max = 40; // últimas N ocorrências
  static const _maxLinha = 600; // corta mensagens/stacks muito longas

  static final List<String> _buffer = [];
  static bool _carregado = false;

  /// Lê o buffer persistido (1x). Chamado no boot; seguro chamar de novo.
  static Future<void> carregar() async {
    if (_carregado) return;
    _carregado = true;
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_chave);
      if (s != null && s.isNotEmpty) {
        _buffer
          ..clear()
          ..addAll((jsonDecode(s) as List).map((e) => '$e'));
      }
    } catch (_) {}
  }

  /// Registra uma ocorrência. `origem` ex.: 'muse', 'tts', 'flutter', 'zona'.
  /// Nunca lança (defensivo — é chamado de dentro de handlers de erro).
  static void registrar(String origem, Object erro, [StackTrace? st]) {
    try {
      final hora = DateTime.now().toIso8601String().substring(0, 19);
      var linha = '[$hora] $origem: $erro';
      if (st != null) {
        final s = st.toString();
        linha += '\n${s.length > _maxLinha ? s.substring(0, _maxLinha) : s}';
      }
      if (linha.length > _maxLinha * 2) linha = linha.substring(0, _maxLinha * 2);
      _buffer.add(linha);
      while (_buffer.length > _max) {
        _buffer.removeAt(0);
      }
      _persistir(); // fire-and-forget
    } catch (_) {}
  }

  static Future<void> _persistir() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_chave, jsonEncode(_buffer));
    } catch (_) {}
  }

  static bool get vazio => _buffer.isEmpty;
  static int get quantidade => _buffer.length;

  /// Relatório legível (cabeçalho + ocorrências), pronto p/ enviar/compartilhar.
  static String texto() {
    final cab = 'Taskix $appVersao • relatório de falhas\n'
        '${_buffer.length} ocorrência(s)\n'
        '${'─' * 32}\n';
    if (_buffer.isEmpty) return '${cab}Nenhuma falha registrada. 🎉';
    return cab + _buffer.join('\n\n');
  }

  static Future<void> limpar() async {
    _buffer.clear();
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_chave);
    } catch (_) {}
  }

  /// Envia o relatório ao proxy do Muse (`/report`) autenticado como o dono.
  /// true se o servidor confirmou. Sem chat habilitado / sem login → false
  /// (o usuário ainda pode COMPARTILHAR o texto por outro canal).
  static Future<bool> enviar() async {
    if (!ChatConfig.habilitado) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    String token;
    try {
      token = (await user.getIdToken()) ?? '';
    } catch (_) {
      return false;
    }
    if (token.isEmpty) return false;
    try {
      final r = await http
          .post(
            Uri.parse('${ChatConfig.url}/report'),
            headers: {
              'content-type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'versao': appVersao, 'relatorio': texto()}),
          )
          .timeout(const Duration(seconds: 20));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
