import 'package:flutter_test/flutter_test.dart';

import 'package:adm_projetos/storage.dart';

/// Recuperação por texto colado (V0.1.58): `projetosDeBackupColado` reconstrói
/// projetos a partir do texto do botão "Copiar backup" ou de um JSON.
/// ⚠️ Dados FICTÍCIOS de propósito — nunca colocar conteúdo real de usuário
/// num teste (o repositório é público).
void main() {
  group('texto do "Copiar backup"', () {
    const backup = '''
ADM-projetos  —  Backup
====================================

- - -
Compras
  1- Leite
  2- Pão
  --- Ideias ---
  Comprar presente

- - -
Vazio

- - -
Trabalho
  Reunião 10h
  Ligar cliente
''';

    test('reconhece os 3 projetos, na ordem', () {
      final ps = projetosDeBackupColado(backup);
      expect(ps.map((p) => p.nome).toList(), ['Compras', 'Vazio', 'Trabalho']);
    });

    test('separa Tarefas e Ideias no marcador', () {
      final ps = projetosDeBackupColado(backup);
      final compras = ps.firstWhere((p) => p.nome == 'Compras');
      expect(compras.tarefas.length, 1);
      expect(compras.tarefas.first.texto, '1- Leite\n2- Pão');
      expect(compras.futuro.length, 1);
      expect(compras.futuro.first.texto, 'Comprar presente');
    });

    test('projeto sem conteúdo vira projeto vazio (nome preservado)', () {
      final ps = projetosDeBackupColado(backup);
      final vazio = ps.firstWhere((p) => p.nome == 'Vazio');
      expect(vazio.tarefas, isEmpty);
      expect(vazio.futuro, isEmpty);
    });

    test('sem Ideias: tudo vai para Tarefas (uma caixinha)', () {
      final ps = projetosDeBackupColado(backup);
      final trab = ps.firstWhere((p) => p.nome == 'Trabalho');
      expect(trab.tarefas.length, 1);
      expect(trab.tarefas.first.texto, 'Reunião 10h\nLigar cliente');
      expect(trab.futuro, isEmpty);
    });

    test('ids gerados são não-vazios e únicos', () {
      final ps = projetosDeBackupColado(backup);
      final ids = ps.map((p) => p.id).toList();
      expect(ids.every((id) => id.isNotEmpty), isTrue);
      expect(ids.toSet().length, ids.length);
    });

    test('um 2º "--- Ideias ---" vira texto dentro da caixinha de Ideias', () {
      const t = '''
- - -
X
  a
  --- Ideias ---
  b
  --- Ideias ---
  c
''';
      final p = projetosDeBackupColado(t).single;
      expect(p.tarefas.first.texto, 'a');
      expect(p.futuro.first.texto, 'b\n--- Ideias ---\nc');
    });
  });

  group('entrada JSON (exportar arquivo)', () {
    test('lista JSON é lida fielmente', () {
      const json =
          '[{"id":"x","nome":"P","tarefas":[{"id":"n","texto":"oi",'
          '"concluida":true,"links":[]}],"futuro":[],"emAndamento":false}]';
      final ps = projetosDeBackupColado(json);
      expect(ps.single.nome, 'P');
      expect(ps.single.tarefas.single.texto, 'oi');
      expect(ps.single.tarefas.single.concluida, isTrue);
    });
  });

  group('bloco JSON completo (Copiar backup novo, lossless)', () {
    test('usa o JSON após o marcador e ignora a parte legível', () {
      const json = '[{"id":"p1","nome":"Proj","tarefas":[{"id":"n1",'
          '"texto":"linha1\\nlinha2","concluida":true,'
          '"comentario":"meu comentario","links":[{"url":"http://x",'
          '"titulo":"T"}]}],"futuro":[],"emAndamento":true}]';
      // A parte de cima tem "- - -"/nome, que o parser de texto pegaria — mas o
      // marcador tem prioridade e traz a restauração FIEL.
      final entrada = 'ADM-projetos — Backup\n====\n\n- - -\nProj\n'
          '  linha legivel ignorada\n\n$marcadorBackupJson\n$json';
      final ps = projetosDeBackupColado(entrada);
      expect(ps.length, 1);
      final p = ps.single;
      expect(p.nome, 'Proj');
      expect(p.emAndamento, isTrue);
      final n = p.tarefas.single;
      expect(n.texto, 'linha1\nlinha2');
      expect(n.concluida, isTrue);
      expect(n.comentario, 'meu comentario');
      expect(n.links.single.url, 'http://x');
      expect(n.links.single.titulo, 'T');
    });
  });

  test('texto vazio ou sem projetos devolve lista vazia', () {
    expect(projetosDeBackupColado(''), isEmpty);
    expect(projetosDeBackupColado('   '), isEmpty);
    expect(projetosDeBackupColado('nada aqui\nsó texto solto'), isEmpty);
  });
}
