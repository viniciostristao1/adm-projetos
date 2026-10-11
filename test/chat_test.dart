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

  group('Conversa', () {
    test('round-trip JSON preserva título, preset e mensagens', () {
      final c = Conversa.nova(ChatPreset.coach)
        ..mensagens = [ChatMessage.usuario('oi'), ChatMessage.ia('olá')]
        ..talvezTitular();
      final v = Conversa.fromJson(c.toJson());
      expect(v.preset, ChatPreset.coach);
      expect(v.titulo, 'oi');
      expect(v.mensagens.length, 2);
      expect(v.mensagens.first.texto, 'oi');
    });

    test('talvezTitular usa a 1ª mensagem do usuário (cortada)', () {
      final c = Conversa.nova(ChatPreset.livre)
        ..mensagens = [ChatMessage.usuario('a' * 60)]
        ..talvezTitular();
      expect(c.titulo.length, 43); // 42 chars + reticências
      expect(c.titulo.endsWith('…'), isTrue);
    });
  });

  group('ChatStore — histórico (chave própria)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('salvar + listar devolve a conversa', () async {
      final c = Conversa.nova(ChatPreset.coach)
        ..mensagens = [ChatMessage.usuario('a')]
        ..talvezTitular();
      await ChatStore.salvar(c);
      final lista = await ChatStore.listar();
      expect(lista.length, 1);
      expect(lista.first.titulo, 'a');
      expect(lista.first.preset, ChatPreset.coach);
    });

    test('salvar duas vezes a MESMA conversa não duplica (upsert)', () async {
      final c = Conversa.nova(ChatPreset.livre)..mensagens = [ChatMessage.ia('x')];
      await ChatStore.salvar(c);
      c.mensagens = [...c.mensagens, ChatMessage.usuario('y')];
      await ChatStore.salvar(c);
      final lista = await ChatStore.listar();
      expect(lista.length, 1);
      expect(lista.first.mensagens.length, 2);
    });

    test('remover apaga a conversa', () async {
      final c = Conversa.nova(ChatPreset.livre)..mensagens = [ChatMessage.ia('x')];
      await ChatStore.salvar(c);
      await ChatStore.remover(c.id);
      expect(await ChatStore.listar(), isEmpty);
    });

    test('migra a conversa antiga (taskix_chat_v1) para uma Conversa', () async {
      SharedPreferences.setMockInitialValues({
        'taskix_chat_v1':
            '[{"role":"user","texto":"oi antigo","hora":1}]',
      });
      final lista = await ChatStore.listar();
      expect(lista.length, 1);
      expect(lista.first.mensagens.first.texto, 'oi antigo');
      final p = await SharedPreferences.getInstance();
      expect(p.getKeys().contains('taskix_chat_v1'), isFalse); // removida
    });

    test('não escreve na chave de projetos (isolado do Storage)', () async {
      final c = Conversa.nova(ChatPreset.livre)..mensagens = [ChatMessage.usuario('oi')];
      await ChatStore.salvar(c);
      final p = await SharedPreferences.getInstance();
      expect(p.getKeys(), {'taskix_muse_convs_v1'});
    });
  });
}
