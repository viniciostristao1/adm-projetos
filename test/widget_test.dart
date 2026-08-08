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
}