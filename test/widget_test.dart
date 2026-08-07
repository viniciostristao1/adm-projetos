import 'package:adm_projetos/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Nota serializa e desserializa', () {
    final nota = Nota(id: '1', texto: 'minha ideia');
    final deVolta = Nota.fromJson(nota.toJson());
    expect(deVolta.id, '1');
    expect(deVolta.texto, 'minha ideia');
  });

  test('Projeto serializa e mantém notas', () {
    final projeto = Projeto(
      id: 'p1',
      nome: 'Projeto A',
      notas: [Nota(id: '1', texto: 'ideia 1'), Nota(id: '2', texto: 'ideia 2')],
    );
    final deVolta = Projeto.fromJson(projeto.toJson());
    expect(deVolta.nome, 'Projeto A');
    expect(deVolta.notas.length, 2);
    expect(deVolta.notas[1].texto, 'ideia 2');
  });

  test('Projeto cria lista de notas vazia', () {
    final projeto = Projeto(id: 'p2', nome: 'B');
    expect(projeto.notas, isEmpty);
  });
}