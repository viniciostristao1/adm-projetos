import 'package:adm_projetos/chat/chat_models.dart';
import 'package:adm_projetos/voz_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Voz da Muse (V0.1.163): velocidade/voz persistidas + "devagar" por conversa.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults (nunca configurado)', () async {
    SharedPreferences.setMockInitialValues({});
    final c = VozController();
    await c.carregar();
    expect(c.velocidade, VozController.velocidadePadrao);
    expect(c.vozId, 'dii');
    expect(c.masculina, isFalse);
    expect(c.rotuloVelocidade, '1.04×');
    expect(c.rotuloVoz, 'Feminina');
  });

  test('roundtrip + faixas e vozes inválidas caem no seguro', () async {
    SharedPreferences.setMockInitialValues({});
    final c = VozController();
    await c.carregar();
    await c.definirVelocidade(9.9);
    expect(c.velocidade, VozController.velocidadeMax);
    await c.definirVelocidade(0.1);
    expect(c.velocidade, VozController.velocidadeMin);
    await c.definirVelocidade(double.nan);
    expect(c.velocidade, VozController.velocidadeMin);
    await c.definirVoz('faber');
    expect(c.masculina, isTrue);
    await c.definirVoz('xx');
    expect(c.vozId, 'faber'); // inválida ignorada

    final d = VozController();
    await d.carregar();
    expect(d.velocidade, VozController.velocidadeMin);
    expect(d.vozId, 'faber');
  });

  test('Conversa.falaDevagar: default false, JSON compatível', () {
    final c = Conversa.nova(ChatPreset.geral);
    expect(c.falaDevagar, isFalse);
    // JSON antigo (sem a chave) carrega como false.
    expect(Conversa.fromJson({}).falaDevagar, isFalse);
    c.falaDevagar = true;
    expect(Conversa.fromJson(c.toJson()).falaDevagar, isTrue);
  });
}
