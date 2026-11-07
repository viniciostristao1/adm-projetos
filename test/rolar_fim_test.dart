import 'package:adm_projetos/chat/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('longeDoFimLista: no fim ou lista curta = false', () {
    expect(longeDoFimLista(1000, 1000), isFalse);
    expect(longeDoFimLista(950, 1000), isFalse); // dentro da margem (120)
    expect(longeDoFimLista(0, 0), isFalse); // lista curta/vazia
    expect(longeDoFimLista(0, 50), isFalse);
  });

  test('longeDoFimLista: acima da margem = true', () {
    expect(longeDoFimLista(800, 1000), isTrue);
    expect(longeDoFimLista(0, 1000), isTrue);
    expect(longeDoFimLista(879, 1000), isTrue);
    expect(longeDoFimLista(880, 1000), isFalse); // exatamente na borda
  });

  test('longeDoFimLista: margem personalizada', () {
    expect(longeDoFimLista(500, 1000, 600), isFalse); // a 500 do fim
    expect(longeDoFimLista(300, 1000, 600), isTrue); // a 700 do fim
  });
}
