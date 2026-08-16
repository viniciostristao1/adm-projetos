import 'package:adm_projetos/editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('digitar normalmente não empilha nada no histórico', () {
    final h = HistoricoTexto()..comecar('', null);
    h.registrar('a', null);
    h.registrar('ab', null);
    h.registrar('abc', null);
    expect(h.podeDesfazer, isFalse);
    expect(h.desfazer(), isNull);
  });

  test('rajada de apagamentos empilha uma vez e desfazer restaura tudo', () {
    final h = HistoricoTexto()..comecar('minha frase bem escrita', null);
    h.registrar('minha frase bem es', null);
    h.registrar('minha frase be', null);
    h.registrar('minha', null);
    h.registrar('mi', null);
    expect(h.podeDesfazer, isTrue);
    final estado = h.desfazer();
    expect(estado?.$1, 'minha frase bem escrita');
    expect(estado?.$2, isNull);
    expect(h.podeDesfazer, isFalse);
  });

  test('apagar e digitar de novo empilha outra rajada', () {
    final h = HistoricoTexto()..comecar('123456', null);
    h.registrar('123', null);
    h.registrar('123x', null); // digitou de novo
    h.registrar('12', null); // nova rajada de apagamento
    expect(h.desfazer()?.$1, '123x');
    expect(h.desfazer()?.$1, '123456');
  });

  test('limpar tudo (texto vazio) pode ser desfeito', () {
    final h = HistoricoTexto()..comecar('conteúdo importante', null);
    h.registrar('', null);
    expect(h.desfazer()?.$1, 'conteúdo importante');
  });

  test('apagar no TÍTULO também empilha (estado com texto + título)', () {
    final h = HistoricoTexto()..comecar('corpo do texto', 'Meu Título');
    h.registrar('corpo do texto', 'Meu');
    final estado = h.desfazer();
    expect(estado?.$1, 'corpo do texto');
    expect(estado?.$2, 'Meu Título');
  });

  test('empilhar guarda o estado antes de uma ação (centralizar, etc.)', () {
    final h = HistoricoTexto()..comecar('uma frase qualquer', null);
    h.empilhar('uma frase qualquer', null); // antes da ação
    h.empilhar('uma frase qualquer', null); // duplicata é ignorada
    h.registrar('uma frase qualquer nova', 'uma frase'); // ação aplicada
    expect(h.podeDesfazer, isTrue);
    final estado = h.desfazer();
    expect(estado?.$1, 'uma frase qualquer');
    expect(estado?.$2, isNull);
    expect(h.podeDesfazer, isFalse);
  });

  test('comecar zera o histórico', () {
    final h = HistoricoTexto()..comecar('x', null);
    h.registrar('', null);
    expect(h.podeDesfazer, isTrue);
    h.comecar('novo texto', null);
    expect(h.podeDesfazer, isFalse);
  });
}
