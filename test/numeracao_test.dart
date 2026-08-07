import 'package:adm_projetos/editor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('proximoNumeroLista', () {
    test('texto vazio -> 1', () {
      expect(proximoNumeroLista(''), 1);
    });

    test('continua sequência existente', () {
      expect(proximoNumeroLista('1- a\n2- b'), 3);
    });

    test('ignora texto sem números', () {
      expect(proximoNumeroLista('apenas um parágrafo'), 1);
    });
  });

  group('LinhasNumeradas (Enter na lista)', () {
    final formatter = LinhasNumeradas();

    TextEditingValue fmt(TextEditingValue novo) =>
        formatter.formatEditUpdate(const TextEditingValue(text: ''), novo);

test('Enter depois de item numerado cria o próximo número', () {
      const novo = TextEditingValue(
        text: '1- comprar pão\n',
        selection: TextSelection.collapsed(offset: 14),
      );
      final r = fmt(novo);
      expect(r.text, '1- comprar pão\n2- ');
    });

    test('sem linha nova, não altera nada', () {
      const novo = TextEditingValue(
        text: 'mercado amanhã',
        selection: TextSelection.collapsed(offset: 14),
      );
      expect(fmt(novo).text, novo.text);
    });

    test('apagar número NÃO é desfeito pelo formatador', () {
      // Backspace apagando toda a linha "2- b": a edição encolhe o texto,
      // então o formatador não re-insere o número.
      final r = formatter.formatEditUpdate(
        const TextEditingValue(
          text: '1- a\n2- b',
          selection: TextSelection.collapsed(offset: 8),
        ),
        const TextEditingValue(
          text: '1- a\n',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      expect(r.text, '1- a\n');
    });

    test('não numera linha nova sem item anterior numerado', () {
      const novo = TextEditingValue(
        text: 'parágrafo normal\n',
        selection: TextSelection.collapsed(offset: 16),
      );
      expect(fmt(novo).text, 'parágrafo normal\n');
    });

    test('Enter numa lista continua 2, 3, 4…', () {
      var v = formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(
          text: '1- a\n',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      // Usuário digita o item 2 e depois dá Enter.
      v = formatter.formatEditUpdate(
        v,
        TextEditingValue(
          text: '${v.text}b',
          selection: TextSelection.collapsed(offset: v.text.length + 1),
        ),
      );
      v = formatter.formatEditUpdate(
        v,
        TextEditingValue(
          text: '${v.text}\n',
          selection: TextSelection.collapsed(offset: v.text.length + 1),
        ),
      );
      expect(v.text, '1- a\n2- b\n3- ');
    });
  });

  group('maiusculaAposItem', () {
    test('maúscula no início do item', () {
      expect(maiusculaAposItem('1- mercado'), '1- Mercado');
    });

    test('não muda texto já maúsculo', () {
      expect(maiusculaAposItem('1- Feira'), '1- Feira');
    });

    test('não muda linha sem número', () {
      expect(maiusculaAposItem('apenas texto'), 'apenas texto');
    });
  });
}