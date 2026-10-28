import 'package:adm_projetos/lembretes.dart';
import 'package:flutter_test/flutter_test.dart';

/// Itens 2 e 3 (V0.1.172): botão "Feito" e alarmes inteligentes (payload muse:).
/// Só lógica pura — sem channel de plataforma.
void main() {
  group('botão Feito', () {
    test('id do botão é estável', () {
      expect(LembretesService.acaoFeitoId, 'feito');
    });
  });

  group('payload do alarme inteligente', () {
    test('monta e extrai (preset + pergunta)', () {
      const p = 'muse:coach:Como foi o treino?';
      expect(LembretesService.payloadMuse('coach', 'Como foi o treino?'), p);
      expect(LembretesService.pedidoMuseDePayload(p),
          (preset: 'coach', pergunta: 'Como foi o treino?'));
    });

    test('pergunta com dois-pontos sobrevive (só o 1º separa)', () {
      const p = 'muse:geral:Hora: vamos revisar 10:30?';
      expect(LembretesService.pedidoMuseDePayload(p),
          (preset: 'geral', pergunta: 'Hora: vamos revisar 10:30?'));
    });

    test('inválidos dão null (não abre a Muse à toa)', () {
      expect(LembretesService.pedidoMuseDePayload(null), isNull);
      expect(LembretesService.pedidoMuseDePayload('Regar as plantas'), isNull);
      expect(LembretesService.pedidoMuseDePayload('muse:coach'), isNull);
      expect(LembretesService.pedidoMuseDePayload('muse:nave:Oi'), isNull);
      expect(LembretesService.pedidoMuseDePayload('muse:coach:  '), isNull);
      expect(LembretesService.pedidoMuseDePayload(''), isNull);
    });
  });
}
