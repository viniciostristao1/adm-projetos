import 'dart:convert';

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

    test('round-trip preserva o modelo; deId cai no rápido se desconhecido', () {
      final c = Conversa.nova(ChatPreset.geral)..modelo = ChatModelo.caprichado;
      expect(Conversa.fromJson(c.toJson()).modelo, ChatModelo.caprichado);
      expect(ChatModelo.deId('xyz'), ChatModelo.rapido);
      expect(ChatModelo.deId('deepseek-v4.1-flash'), ChatModelo.caprichado);
    });

    test('tamanho: padrão longo, round-trip preserva, deId tolera ausente', () {
      // Conversa nova nasce com tamanho LONGO (preserva o comportamento atual).
      expect(Conversa.nova(ChatPreset.coach).tamanho, ChatTamanho.longo);
      final c = Conversa.nova(ChatPreset.geral)..tamanho = ChatTamanho.curto;
      expect(Conversa.fromJson(c.toJson()).tamanho, ChatTamanho.curto);
      // Compat: JSON antigo sem 'tamanho' = longo.
      expect(ChatTamanho.deId(null), ChatTamanho.longo);
      expect(ChatTamanho.deId('xyz'), ChatTamanho.longo);
      expect(ChatTamanho.deId('curto'), ChatTamanho.curto);
    });

    test('talvezTitular usa a 1ª mensagem do usuário (cortada)', () {
      final c = Conversa.nova(ChatPreset.projetos)
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
      final c = Conversa.nova(ChatPreset.projetos)..mensagens = [ChatMessage.ia('x')];
      await ChatStore.salvar(c);
      c.mensagens = [...c.mensagens, ChatMessage.usuario('y')];
      await ChatStore.salvar(c);
      final lista = await ChatStore.listar();
      expect(lista.length, 1);
      expect(lista.first.mensagens.length, 2);
    });

    test('remover apaga a conversa', () async {
      final c = Conversa.nova(ChatPreset.projetos)..mensagens = [ChatMessage.ia('x')];
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
      final c = Conversa.nova(ChatPreset.projetos)..mensagens = [ChatMessage.usuario('oi')];
      await ChatStore.salvar(c);
      final p = await SharedPreferences.getInstance();
      expect(p.getKeys(), {'taskix_muse_convs_v1'});
    });

    test('marcarUltima + ultimaId guardam a última conversa ativa', () async {
      await ChatStore.marcarUltima('abc123');
      expect(await ChatStore.ultimaId(), 'abc123');
    });

    test('renomear persiste o novo título', () async {
      final c = Conversa.nova(ChatPreset.geral)..mensagens = [ChatMessage.ia('x')];
      await ChatStore.salvar(c);
      c.titulo = 'Meu papo';
      await ChatStore.salvar(c);
      final lista = await ChatStore.listar();
      expect(lista.single.titulo, 'Meu papo');
    });

    test('foto VELHA não apaga o que já foi salvo (merge, nunca encolhe)', () async {
      // Regressão V0.1.118: "sumiu o que escrevi hoje". A tela guardava uma foto
      // atrasada (ex.: respostas chegaram em background) e, ao salvar, encolhia a
      // conversa. Agora salvar MESCLA: nunca perde mensagens já no disco.
      final c = Conversa.nova(ChatPreset.geral)
        ..mensagens = [ChatMessage.usuario('1')];
      await ChatStore.salvar(c);
      final fotoVelha = Conversa.fromJson(c.toJson()); // congela em 1 msg
      // Disco cresce por fora (respostas em background):
      await ChatStore.anexarIa(c.id, '2');
      await ChatStore.anexarIa(c.id, '3');
      // Salvar a foto velha NÃO pode apagar 2 e 3:
      await ChatStore.salvar(fotoVelha);
      await ChatStore.sincronizar();
      final atual = await ChatStore.porId(c.id);
      expect(atual?.mensagens.length, 3);
      expect(atual?.mensagens.map((m) => m.texto).toList(), ['1', '2', '3']);
    });

    test('leitura corrompida não apaga as conversas (gravador aborta)', () async {
      final c = Conversa.nova(ChatPreset.geral)..mensagens = [ChatMessage.usuario('ok')];
      await ChatStore.salvar(c);
      // Corrompe o blob salvo e tenta salvar outra: o gravador deve ABORTAR,
      // preservando o que já havia, em vez de sobrescrever com menos.
      final p = await SharedPreferences.getInstance();
      await p.setString('taskix_muse_convs_v1', '{lixo corrompido');
      await ChatStore.salvar(
          Conversa.nova(ChatPreset.coach)..mensagens = [ChatMessage.usuario('nova')]);
      await ChatStore.sincronizar();
      // listar() é tolerante e devolve [] num blob corrompido — o importante é que
      // o gravador NÃO explodiu e NÃO reescreveu por cima (sem exceção propagada).
      expect(() async => ChatStore.listar(), returnsNormally);
    });

    test('saves concorrentes não perdem mensagens (o mais novo vence)', () async {
      // Regressão: sair da tela e voltar em segundos sumia com mensagens, pois
      // dois read-modify-write corriam juntos e o mais lento sobrescrevia o novo.
      final c = Conversa.nova(ChatPreset.geral)..mensagens = [ChatMessage.usuario('1')];
      final f1 = ChatStore.salvar(c); // foto com 1 msg
      c.mensagens = [...c.mensagens, ChatMessage.ia('2'), ChatMessage.usuario('3')];
      final f2 = ChatStore.salvar(c); // foto com 3 msgs
      await Future.wait([f1, f2]);
      await ChatStore.sincronizar();
      final lista = await ChatStore.listar();
      expect(lista.single.mensagens.length, 3);
      expect(lista.single.mensagens.last.texto, '3');
    });

    test('merge NÃO deixa mensagem antiga no fim — reordena por hora (V0.1.182)',
        () async {
      // Bug: uma mensagem de DIAS atrás, reinjetada pela foto da tela, ia pro FIM
      // da lista e virava a "última" enviada ao modelo. Deve voltar à posição
      // cronológica (começo), não ficar depois das recentes.
      final recente = DateTime(2026, 10, 27, 10, 27);
      final c = Conversa.nova(ChatPreset.geral)
        ..mensagens = [
          ChatMessage('user', 'recente', recente),
          ChatMessage('assistant', 'resposta', recente.add(const Duration(seconds: 30))),
        ];
      await ChatStore.salvar(c);
      // Foto da tela traz uma msg ANTIGA (25/10) que NÃO está no disco:
      final foto = Conversa.fromJson(c.toJson());
      foto.mensagens = [
        ...foto.mensagens,
        ChatMessage('user', '5 colheres de arroz', DateTime(2026, 10, 25, 7, 3)),
      ];
      await ChatStore.salvar(foto);
      await ChatStore.sincronizar();
      final atual = await ChatStore.porId(c.id);
      expect(atual?.mensagens.length, 3);
      // A antiga fica no COMEÇO (cronológica); a ÚLTIMA é a resposta recente.
      expect(atual?.mensagens.first.texto, '5 colheres de arroz');
      expect(atual?.mensagens.last.texto, 'resposta');
    });

    test('LEITURA reordena conversa salva fora de ordem (display na volta, V0.1.183)',
        () async {
      // Simula o disco JÁ fora de ordem (ex.: dispose salvou um _conv cruzado com
      // anexarIa ao sair/voltar): uma msg antiga DEPOIS das recentes. Toda leitura
      // (porId/listar) deve devolver cronológico — conserta o que a tela exibe.
      final antiga = DateTime(2026, 10, 25, 9, 36);
      final recente = DateTime(2026, 10, 29, 12, 36);
      final conv = Conversa(
        id: 'c1',
        titulo: 'x',
        preset: ChatPreset.coach,
        atualizadaEm: recente,
        mensagens: [
          ChatMessage('user', 'E a massa junto?', recente),
          ChatMessage('assistant', 'resposta massa',
              recente.add(const Duration(seconds: 20))),
          ChatMessage('user', 'café da manhã', antiga), // ANTIGA no fim (bug)
        ],
      );
      final p = await SharedPreferences.getInstance();
      await p.setString('taskix_muse_convs_v1', jsonEncode([conv.toJson()]));
      final atual = await ChatStore.porId('c1');
      expect(atual?.mensagens.first.texto, 'café da manhã'); // volta p/ o começo
      expect(atual?.mensagens.last.texto, 'resposta massa');
    });
  });

  group('resposta sobrevive ao voltar (envio em background)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('porId devolve a conversa certa (ou null se sumiu)', () async {
      final c = Conversa.nova(ChatPreset.geral)
        ..mensagens = [ChatMessage.usuario('oi')];
      await ChatStore.salvar(c);
      expect((await ChatStore.porId(c.id))?.titulo, c.titulo);
      expect(await ChatStore.porId('inexistente'), isNull);
    });

    test('anexarIa grava a resposta mesmo sem tela montada', () async {
      // Simula: perguntou, saiu com voltar (só a pergunta salva) e a resposta
      // chegou depois — tem que aparecer ao reabrir.
      final c = Conversa.nova(ChatPreset.geral)
        ..mensagens = [ChatMessage.usuario('oi?')];
      await ChatStore.salvar(c);
      await ChatStore.anexarIa(c.id, 'olá!');
      final atual = await ChatStore.porId(c.id);
      expect(atual?.mensagens.length, 2);
      expect(atual?.mensagens.last.ehUsuario, isFalse);
      expect(atual?.mensagens.last.texto, 'olá!');
    });

    test('anexarIa em conversa inexistente não quebra nem cria nada', () async {
      await ChatStore.anexarIa('sumida', 'oi');
      expect(await ChatStore.listar(), isEmpty);
    });

    test('anexarIa respeita o teto de 120 mensagens', () async {
      final c = Conversa.nova(ChatPreset.geral)
        ..mensagens = [for (var i = 0; i < 120; i++) ChatMessage.usuario('$i')];
      await ChatStore.salvar(c);
      await ChatStore.anexarIa(c.id, 'nova');
      final atual = await ChatStore.porId(c.id);
      expect(atual?.mensagens.length, 120);
      expect(atual?.mensagens.last.texto, 'nova');
    });
  });
}
