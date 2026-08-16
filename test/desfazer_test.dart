import 'package:adm_projetos/editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('digitar uma rajada (sem pausa) cria UM ponto de desfazer', () {
    final h = HistoricoTexto()..comecar('');
    h.registrar('a');
    h.registrar('ab');
    h.registrar('abc');
    // Teclas seguidas do mesmo tipo e sem pausa são um só movimento — o
    // desfazer volta o bloco inteiro para o estado anterior.
    expect(h.podeDesfazer, isTrue);
    expect(h.desfazer(), '');
    expect(h.podeDesfazer, isFalse);
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

  test('apagar, digitar e apagar de novo cria movimentos separados', () {
    final h = HistoricoTexto()..comecar('123456');
    h.registrar('123'); // apagou (1º movimento)
    h.registrar('123x'); // digitou de novo (trocou o sentido)
    h.registrar('12'); // apagou de novo (trocou o sentido)
    // Cada troca de sentido é um novo movimento desfazível.
    expect(h.desfazer(), '123x');
    expect(h.desfazer(), '123');
    expect(h.desfazer(), '123456');
  });

  test('pausa entre digitações cria níveis de desfazer separados', () async {
    final h = HistoricoTexto(pausaMs: 5)..comecar('');
    h.registrar('ola'); // 1º movimento (empilha '')
    await Future<void>.delayed(const Duration(milliseconds: 20));
    h.registrar('ola mundo'); // pausa -> novo movimento (empilha 'ola')
    expect(h.desfazer(), 'ola');
    expect(h.desfazer(), '');
    expect(h.podeDesfazer, isFalse);
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
