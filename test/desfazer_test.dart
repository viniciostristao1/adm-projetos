import 'package:adm_projetos/editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('digitar normalmente não empilha nada no histórico', () {
    final h = HistoricoTexto()..comecar('');
    h.registrar('a');
    h.registrar('ab');
    h.registrar('abc');
    expect(h.podeDesfazer, isFalse);
    expect(h.desfazer(), isNull);
  });

  test('rajada de apagamentos empilha uma vez e desfazer restaura tudo', () {
    final h = HistoricoTexto()..comecar('minha frase bem escrita');
    h.registrar('minha frase bem es');
    h.registrar('minha frase be');
    h.registrar('minha');
    h.registrar('mi');
    expect(h.podeDesfazer, isTrue);
    expect(h.desfazer(), 'minha frase bem escrita');
    expect(h.podeDesfazer, isFalse);
  });

  test('apagar e digitar de novo empilha outra rajada', () {
    final h = HistoricoTexto()..comecar('123456');
    h.registrar('123');
    h.registrar('123x'); // digitou de novo
    h.registrar('12'); // nova rajada de apagamento
    expect(h.desfazer(), '123x');
    expect(h.desfazer(), '123456');
  });

  test('limpar tudo (texto vazio) pode ser desfeito', () {
    final h = HistoricoTexto()..comecar('conteúdo importante');
    h.registrar('');
    expect(h.desfazer(), 'conteúdo importante');
  });

  test('empilhar guarda o estado antes de uma ação (centralizar, etc.)', () {
    final h = HistoricoTexto()..comecar('uma frase qualquer');
    h.empilhar('uma frase qualquer'); // antes da ação
    h.empilhar('uma frase qualquer'); // duplicata é ignorada
    h.registrar('uma frase qualquer nova'); // ação aplicada
    expect(h.podeDesfazer, isTrue);
    expect(h.desfazer(), 'uma frase qualquer');
    expect(h.podeDesfazer, isFalse);
  });

  test('comecar zera o histórico', () {
    final h = HistoricoTexto()..comecar('x');
    h.registrar('');
    expect(h.podeDesfazer, isTrue);
    h.comecar('novo texto');
    expect(h.podeDesfazer, isFalse);
  });
}
