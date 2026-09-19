import 'package:adm_projetos/lembretes.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testes do rótulo com DIA DA SEMANA por extenso usado no resumo do modo
/// "monte o tempo (vai somando)" do lembrete rápido.
void main() {
  test('formata data + horário + dia da semana (exemplo do usuário)', () {
    // 22/09/2026 é uma terça-feira.
    expect(quandoComDiaSemana(DateTime(2026, 9, 22, 9, 0)),
        '22/09 • 09:00 • Terça-feira');
  });

  test('dia e mês com um dígito ganham zero à esquerda; hora também', () {
    // 05/01/2026 é uma segunda-feira.
    expect(quandoComDiaSemana(DateTime(2026, 1, 5, 8, 5)),
        '05/01 • 08:05 • Segunda-feira');
  });

  test('todos os dias da semana por extenso (sem abreviar)', () {
    // Semana de 21/09/2026 (segunda) a 27/09/2026 (domingo).
    final esperado = [
      'Segunda-feira',
      'Terça-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sábado',
      'Domingo',
    ];
    for (var i = 0; i < 7; i++) {
      final roda = quandoComDiaSemana(DateTime(2026, 9, 21 + i, 12, 0));
      expect(roda, '${(21 + i).toString().padLeft(2, '0')}/09 • 12:00 '
          '• ${esperado[i]}');
    }
  });

  test('meia-noite e fim do dia formatam certo', () {
    expect(quandoComDiaSemana(DateTime(2026, 9, 19, 0, 0)),
        '19/09 • 00:00 • Sábado');
    expect(quandoComDiaSemana(DateTime(2026, 9, 19, 23, 59)),
        '19/09 • 23:59 • Sábado');
  });
}
