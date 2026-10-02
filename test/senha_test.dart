import 'package:adm_projetos/models.dart';
import 'package:adm_projetos/seguranca.dart';
import 'package:flutter_test/flutter_test.dart';

/// Senha de projeto (tranca de conveniência, V0.1.93): o hash confere e a
/// serialização preserva a senha E o conteúdo (a REGRA DE OURO exige que o
/// round-trip de backup/nuvem nunca perca nada).
void main() {
  group('hashSenha / gerarSalt', () {
    test('determinístico: mesmo salt + senha → mesmo hash', () {
      const salt = 'abc123';
      expect(hashSenha('minhaSenha', salt), hashSenha('minhaSenha', salt));
    });

    test('senha errada não confere', () {
      final salt = gerarSalt();
      final h = hashSenha('certa', salt);
      expect(hashSenha('errada', salt), isNot(h));
    });

    test('mesmo texto, salts diferentes → hashes diferentes', () {
      expect(hashSenha('x', gerarSalt()), isNot(hashSenha('x', gerarSalt())));
    });

    test('nunca guarda a senha em texto puro (é SHA-256 hex)', () {
      final h = hashSenha('segredo', 'sal');
      expect(h.contains('segredo'), isFalse);
      expect(h.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(h), isTrue);
    });

    test('gerarSalt é aleatório', () {
      expect(gerarSalt(), isNot(gerarSalt()));
    });
  });

  group('Projeto com senha — serialização', () {
    test('round-trip preserva senhaHash/senhaSalt E o conteúdo', () {
      final salt = gerarSalt();
      final p = Projeto(
        id: '1',
        nome: 'Secreto',
        tarefas: [Nota(id: 'n1', texto: 'conteúdo importante')],
        senhaHash: hashSenha('123', salt),
        senhaSalt: salt,
      );
      final r = Projeto.fromJson(p.toJson());
      expect(r.senhaHash, p.senhaHash);
      expect(r.senhaSalt, p.senhaSalt);
      expect(r.temSenha, isTrue);
      expect(r.tarefas.single.texto, 'conteúdo importante');
      // A senha ainda confere depois do round-trip (backup/restore não quebra).
      expect(hashSenha('123', r.senhaSalt!), r.senhaHash);
    });

    test('sem senha: campos omitidos no JSON e temSenha=false', () {
      final p = Projeto(id: '2', nome: 'Aberto');
      final json = p.toJson();
      expect(json.containsKey('senhaHash'), isFalse);
      expect(json.containsKey('senhaSalt'), isFalse);
      expect(Projeto.fromJson(json).temSenha, isFalse);
    });

    test('JSON antigo (sem os campos) carrega como sem senha', () {
      final r = Projeto.fromJson({'id': '3', 'nome': 'Antigo'});
      expect(r.temSenha, isFalse);
      expect(r.senhaHash, isNull);
      expect(r.senhaSalt, isNull);
    });
  });
}
