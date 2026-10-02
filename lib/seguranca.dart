import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Tranca de CONVENIÊNCIA para projetos (NÃO é criptografia).
///
/// Guardamos só o SHA-256 salgado da senha — NUNCA a senha em texto puro e
/// NUNCA o conteúdo criptografado. Motivo: a REGRA DE OURO do app é *nunca
/// perder conteúdo*. Se criptografássemos e o usuário esquecesse a senha, os
/// dados seriam perdidos para sempre. Com hash, esquecer a senha só impede
/// ABRIR o projeto pela tela — o conteúdo continua íntegro no backup/arquivo
/// exportado (recuperável). A proteção é contra olhares casuais, não forense.

/// Salt aleatório (base64 url-safe) gerado por projeto ao definir a senha.
String gerarSalt([int bytes = 12]) {
  final r = Random.secure();
  final b = List<int>.generate(bytes, (_) => r.nextInt(256));
  return base64Url.encode(b);
}

/// SHA-256 de `salt:senha` em hex. Determinístico (mesmo salt + senha → mesmo
/// hash), usado tanto para gravar quanto para conferir.
String hashSenha(String senha, String salt) =>
    sha256.convert(utf8.encode('$salt:$senha')).toString();
