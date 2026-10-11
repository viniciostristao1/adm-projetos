import 'package:adm_projetos/chat/chat_config.dart';
import 'package:adm_projetos/chat/chat_models.dart';
import 'package:adm_projetos/chat/chat_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('separação (flag de compilação)', () {
    test('sem --dart-define=CHAT, o recurso fica DESLIGADO (build sem chat)', () {
      // Em `flutter test` normal não há dart-define -> o chat (e o botão) somem.
      expect(ChatConfig.habilitado, isFalse);
    });
  });

  group('capitalizarFrases (o que o usuário envia)', () {
    test('capitaliza início do texto e após pontuação', () {
      expect(capitalizarFrases('oi treinador. como vou? etc. isso'),
          'Oi treinador. Como vou? Etc. Isso');
    });
    test('não mexe em decimais/carga (sem espaço após o ponto)', () {
      expect(capitalizarFrases('valor 1.500 e 3.5kg. foi bom'),
          'Valor 1.500 e 3.5kg. Foi bom');
    });
    test('respeita acentos e letras já maiúsculas', () {
      expect(capitalizarFrases('ótimo. É isso'), 'Ótimo. É isso');
    });
    test('texto vazio não quebra', () {
      expect(capitalizarFrases(''), '');
    });
  });

  group('ChatMessage', () {
    test('round-trip JSON preserva role, texto e hora', () {
      final m = ChatMessage.usuario('oi, treinador');
      final v = ChatMessage.fromJson(m.toJson());
      expect(v.role, 'user');
      expect(v.ehUsuario, isTrue);
      expect(v.texto, 'oi, treinador');
      expect(v.hora.millisecondsSinceEpoch, m.hora.millisecondsSinceEpoch);
    });

    test('fromJson tolera campos ausentes', () {
      final v = ChatMessage.fromJson(const {});
      expect(v.role, 'assistant');
      expect(v.ehUsuario, isFalse);
      expect(v.texto, '');
    });
  });

  group('ChatStore (local, chave própria)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('salvar + carregar devolve as mesmas mensagens', () async {
      final msgs = [ChatMessage.usuario('a'), ChatMessage.ia('b')];
      await ChatStore.salvar(msgs);
      final lido = await ChatStore.carregar();
      expect(lido.length, 2);
      expect(lido[0].texto, 'a');
      expect(lido[1].ehUsuario, isFalse);
    });

    test('mantém só as últimas 60', () async {
      final muitas =
          List.generate(80, (i) => ChatMessage.usuario('m$i'));
      await ChatStore.salvar(muitas);
      final lido = await ChatStore.carregar();
      expect(lido.length, 60);
      expect(lido.first.texto, 'm20'); // cortou as 20 primeiras
      expect(lido.last.texto, 'm79');
    });

    test('limpar esvazia', () async {
      await ChatStore.salvar([ChatMessage.ia('x')]);
      await ChatStore.limpar();
      expect(await ChatStore.carregar(), isEmpty);
    });

    test('não escreve na chave de projetos (isolado do Storage)', () async {
      await ChatStore.salvar([ChatMessage.usuario('oi')]);
      final p = await SharedPreferences.getInstance();
      // a única chave tocada é a do chat
      expect(p.getKeys(), {'taskix_chat_v1'});
    });
  });
}
