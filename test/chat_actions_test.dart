import 'package:adm_projetos/chat/chat_actions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ações da Muse (V0.1.163): bloco [[ACAO:...]] parseado e executado no app.
/// Executores reais (alarme/Storage) entram por injeção — aqui vão fakes.
void main() {
  group('extrair', () {
    test('lembrete válido (chaves case-insensitive, espaços soltos)', () {
      final a = ChatActions.extrair(
          'Claro!\n[[ACAO:lembrete | TEXTO = Ligar pro João | quando = 2026-10-26 09:00 ]]');
      expect(a, hasLength(1));
      expect(a[0].tipo, 'lembrete');
      expect(a[0].params['texto'], 'Ligar pro João');
      expect(a[0].params['quando'], '2026-10-26 09:00');
    });

    test('nota com projeto default quando ausente', () {
      final a = ChatActions.extrair(
          '[[ACAO:nota | texto=Ver o capítulo 3]]');
      expect(a, hasLength(1));
      expect(a[0].tipo, 'nota');
      expect(a[0].params['projeto'], isNull);
    });

    test('ignora tipo desconhecido e bloco quebrado', () {
      expect(ChatActions.extrair('[[ACAO:foguete | texto=x]]'), isEmpty);
      expect(ChatActions.extrair('[[ACAO:lembrete | texto=x'), isEmpty);
      expect(ChatActions.extrair('sem bloco nenhum'), isEmpty);
    });
  });

  group('limpar', () {
    test('tira os blocos e colapsa brancos', () {
      expect(
        ChatActions.limpar(
            'Oi!\n\n[[ACAO:nota | texto=x]]\n\n\nAté mais.'),
        'Oi!\n\nAté mais.',
      );
      expect(ChatActions.limpar('só texto'), 'só texto');
    });
  });

  group('executarTodos', () {
    test('lembrete futuro agenda e confirma (texto limpo)', () async {
      var chamado = 0;
      String? salvoTexto;
      DateTime? salvoQuando;
      final r = await ChatActions.executarTodos(
        'Fechado!\n[[ACAO:lembrete | texto=Regar as plantas | quando=2999-01-02 09:00]]',
        agendar: (t, q, {abrir, dizer}) async {
          chamado++;
          salvoTexto = t;
          salvoQuando = q;
          return true;
        },
      );
      expect(chamado, 1);
      expect(salvoTexto, 'Regar as plantas');
      expect(salvoQuando, DateTime(2999, 1, 2, 9, 0));
      expect(r.texto, 'Fechado!');
      expect(r.confirmacoes, hasLength(1));
      expect(r.confirmacoes[0], contains('Regar as plantas'));
    });

    test('data passada não agenda (avisa)', () async {
      var chamado = 0;
      final r = await ChatActions.executarTodos(
        '[[ACAO:lembrete | texto=X | quando=2020-01-01 09:00]]',
        agendar: (texto, quando, {abrir, dizer}) async {
          chamado++;
          return true;
        },
      );
      expect(chamado, 0);
      expect(r.texto, isEmpty);
      expect(r.confirmacoes.single, contains('já passou'));
    });

    test('nota salva (Estudos por padrão) e confirma', () async {
      String? proj;
      String? txt;
      final r = await ChatActions.executarTodos(
        '[[ACAO:nota | texto=Ler o cap 3]]',
        salvar: (p, t) async {
          proj = p;
          txt = t;
        },
      );
      expect(proj, 'Estudos');
      expect(txt, 'Ler o cap 3');
      expect(r.confirmacoes.single, contains('Estudos'));
    });

    test('completo:false só limpa, sem executar (anti-duplicado do fallback)',
        () async {
      var agendou = false;
      var salvou = false;
      final r = await ChatActions.executarTodos(
        'Oi [[ACAO:lembrete | texto=X | quando=2999-01-02 09:00]]',
        completo: false,
        agendar: (texto, quando, {abrir, dizer}) async {
          agendou = true;
          return true;
        },
        salvar: (proj, texto) async => salvou = true,
      );
      expect(agendou, isFalse);
      expect(salvou, isFalse);
      expect(r.texto, 'Oi');
      expect(r.confirmacoes, isEmpty);
    });

    test('no máximo 2 ações por resposta', () async {
      var n = 0;
      final r = await ChatActions.executarTodos(
        '[[ACAO:nota | texto=a]]\n[[ACAO:nota | texto=b]]\n[[ACAO:nota | texto=c]]',
        salvar: (p, t) async => n++,
      );
      expect(n, 2);
      expect(r.confirmacoes, hasLength(2));
    });

    test('texto gigante ou vazio é ignorado em silêncio', () async {
      var n = 0;
      final longo = 'x' * 201;
      final r = await ChatActions.executarTodos(
        '[[ACAO:lembrete | texto=$longo | quando=2999-01-02 09:00]]\n'
        '[[ACAO:nota | texto=  ]]',
        agendar: (texto, quando, {abrir, dizer}) async {
          n++;
          return true;
        },
        salvar: (proj, texto) async => n++,
      );
      expect(n, 0);
      expect(r.confirmacoes, isEmpty);
    });

    test('falha na execução vira aviso (não lança)', () async {
      final r = await ChatActions.executarTodos(
        '[[ACAO:nota | texto=x]]',
        salvar: (proj, texto) async => throw StateError('disco'),
      );
      expect(r.confirmacoes.single, contains('Não consegui'));
    });

    test('alarme inteligente: abrir/dizer chegam ao agendar', () async {
      String? salvoAbrir;
      String? salvoDizer;
      final r = await ChatActions.executarTodos(
        '[[ACAO:lembrete | texto=Treino | quando=2999-01-02 06:30 | abrir=coach | dizer=Como foi o treino?]]',
        agendar: (t, q, {abrir, dizer}) async {
          salvoAbrir = abrir;
          salvoDizer = dizer;
          return true;
        },
      );
      expect(salvoAbrir, 'coach');
      expect(salvoDizer, 'Como foi o treino?');
      expect(r.confirmacoes.single, contains('abre a Muse'));
    });

    test('alarme inteligente: abrir inválido e dizer gigante são ignorados',
        () async {
      String? salvoAbrir = 'x';
      String? salvoDizer = 'y';
      final r = await ChatActions.executarTodos(
        '[[ACAO:lembrete | texto=X | quando=2999-01-02 09:00 | abrir=nave | dizer=${'z' * 201}]]',
        agendar: (t, q, {abrir, dizer}) async {
          salvoAbrir = abrir;
          salvoDizer = dizer;
          return true;
        },
      );
      expect(salvoAbrir, isNull);
      expect(salvoDizer, isNull);
      expect(r.confirmacoes.single, isNot(contains('abre a Muse')));
    });

    test('sem abrir/dizer o agendar recebe null (compatível)', () async {
      var chamou = false;
      await ChatActions.executarTodos(
        '[[ACAO:lembrete | texto=X | quando=2999-01-02 09:00]]',
        agendar: (t, q, {abrir, dizer}) async {
          chamou = true;
          expect(abrir, isNull);
          expect(dizer, isNull);
          return true;
        },
      );
      expect(chamou, isTrue);
    });
  });

  group('QuickReplies (respostas de 1 toque)', () {
    test('extrai as opções do bloco [[SUGESTOES:...]] (máx. 2)', () {
      final ops = QuickReplies.extrair(
          'Quer que eu monte o alvo?\n[[SUGESTOES: Sim, monta | Prefiro só dicas | Agora não]]');
      expect(ops, ['Sim, monta', 'Prefiro só dicas']);
    });

    test('sem bloco = vazio', () {
      expect(QuickReplies.extrair('Resposta normal sem pergunta.'), isEmpty);
    });

    test('ignora opções vazias/longas e limita a 2', () {
      final longa = 'x' * 80;
      final ops = QuickReplies.extrair(
          '[[SUGESTOES: Um |  | $longa | Dois | Três]]');
      expect(ops, ['Um', 'Dois']);
    });
  });
}
