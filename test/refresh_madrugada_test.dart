import 'package:adm_projetos/refresh_madrugada.dart';
import 'package:flutter_test/flutter_test.dart';

// 06/11/2026 = sexta; 08/11/2026 = domingo.
Map<String, String> dia(String data, [String titulo = 'T']) =>
    {'data': data, 'titulo': titulo, 'corpo': 'C'};

void main() {
  test('proximaMadrugada: antes das 05:30 vale hoje, depois vale amanhã', () {
    expect(proximaMadrugada(DateTime(2026, 11, 6, 4, 0)),
        DateTime(2026, 11, 6, 5, 30));
    expect(proximaMadrugada(DateTime(2026, 11, 6, 6, 0)),
        DateTime(2026, 11, 7, 5, 30));
    // em cima da hora já conta como passada (vai p/ o dia seguinte)
    expect(proximaMadrugada(DateTime(2026, 11, 6, 5, 30)),
        DateTime(2026, 11, 7, 5, 30));
  });

  test('slots: pula domingo e 6:15 de hoje já passada (máx. 3)', () {
    final dias = [
      dia('2026-11-06', 'SEX'),
      dia('2026-11-07', 'SAB'),
      dia('2026-11-08', 'DOM'),
      dia('2026-11-09', 'SEG'),
      dia('2026-11-10', 'TER'),
    ];
    // sexta 09:54 → hoje passou; domingo pula: SAB, SEG, TER
    final slots = calcularSlotsTempo(dias, DateTime(2026, 11, 6, 9, 54));
    expect(slots.map((s) => s.titulo), ['SAB', 'SEG', 'TER']);
    expect(slots.map((s) => s.slot), [0, 1, 2]);
    expect(slots[0].quandoLocal, DateTime(2026, 11, 7, 6, 15));
  });

  test('slots: 05:00 inclui o 6:15 de hoje', () {
    final dias = [
      dia('2026-11-06', 'SEX'),
      dia('2026-11-07', 'SAB'),
      dia('2026-11-08', 'DOM'),
      dia('2026-11-09', 'SEG'),
    ];
    final slots = calcularSlotsTempo(dias, DateTime(2026, 11, 6, 5, 0));
    expect(slots.map((s) => s.titulo), ['SEX', 'SAB', 'SEG']);
  });

  test('slots: dia sem dado é pulado; título vazio vira padrão', () {
    final dias = [
      dia('2026-11-07', ''),
      dia('2026-11-09', 'SEG'),
    ];
    final slots = calcularSlotsTempo(dias, DateTime(2026, 11, 6, 9, 54));
    // SAB sem título → 'Previsão do tempo'; DOM (08) nem tem dado
    expect(slots.map((s) => s.titulo), ['Previsão do tempo', 'SEG']);
  });

  test('slots: lista vazia = nenhum slot', () {
    expect(calcularSlotsTempo([], DateTime(2026, 11, 6, 9, 54)), isEmpty);
  });
}
