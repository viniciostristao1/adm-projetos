import 'package:adm_projetos/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Nota serializa e desserializa', () {
    final nota = Nota(id: '1', texto: 'minha ideia');
    final deVolta = Nota.fromJson(nota.toJson());
    expect(deVolta.id, '1');
    expect(deVolta.texto, 'minha ideia');
  });

  test('Projeto serializa e mantém tarefas', () {
    final projeto = Projeto(
      id: 'p1',
      nome: 'Projeto A',
      tarefas: [Nota(id: '1', texto: 'ideia 1'), Nota(id: '2', texto: 'ideia 2')],
    );
    final deVolta = Projeto.fromJson(projeto.toJson());
    expect(deVolta.nome, 'Projeto A');
    expect(deVolta.tarefas.length, 2);
    expect(deVolta.tarefas[1].texto, 'ideia 2');
  });

  test('Projeto cria listas vazias', () {
    final projeto = Projeto(id: 'p2', nome: 'B');
    expect(projeto.tarefas, isEmpty);
    expect(projeto.futuro, isEmpty);
  });

  test('Projeto migra notas antigas para tarefas', () {
    final json = {
      'id': 'p3',
      'nome': 'Migrado',
      'notas': [
        {'id': '1', 'texto': 'velha ideia'}
      ]
    };
    final p = Projeto.fromJson(json);
    expect(p.tarefas.length, 1);
    expect(p.tarefas.first.texto, 'velha ideia');
    expect(p.futuro, isEmpty);
  });

  test('Nota serializa até 3 links com título', () {
    final nota = Nota(id: '1', texto: 'x', links: [
      NotaLink(url: 'https://youtu.be/abc', titulo: 'Vídeo 1'),
      NotaLink(url: 'https://example.com'),
    ]);
    final deVolta = Nota.fromJson(nota.toJson());
    expect(deVolta.links.length, 2);
    expect(deVolta.links[0].url, 'https://youtu.be/abc');
    expect(deVolta.links[0].titulo, 'Vídeo 1');
    expect(deVolta.links[1].titulo, isNull);
  });

  test('Nota migra link antigo para links[0] e limpa comentário-eco', () {
    final json = {
      'id': '1',
      'texto': 'x',
      'link': 'https://youtu.be/abc',
      'comentario': 'Título do vídeo',
    };
    final n = Nota.fromJson(json);
    expect(n.links.length, 1);
    expect(n.links[0].url, 'https://youtu.be/abc');
    expect(n.links[0].titulo, 'Título do vídeo');
    expect(n.comentario, isNull);
  });

  test('Nota sem links antigos mantém o comentário manual', () {
    final n = Nota.fromJson({'id': '1', 'texto': 'x', 'comentario': 'lembrete'});
    expect(n.links, isEmpty);
    expect(n.comentario, 'lembrete');
  });

  test('Nota serializa o título centralizado', () {
    final nota = Nota(id: '1', texto: 'corpo', titulo: 'Meu título');
    final deVolta = Nota.fromJson(nota.toJson());
    expect(deVolta.titulo, 'Meu título');
    final sem = Nota.fromJson({'id': '1', 'texto': 'x'});
    expect(sem.titulo, isNull);
  });
}