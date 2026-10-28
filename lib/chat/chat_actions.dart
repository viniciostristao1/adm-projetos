import '../lembretes.dart';
import '../storage.dart';

/// Ação pedida pela IA numa resposta (bloco `[[ACAO:...]]` emitido pelo proxy
/// quando o usuário pede EXPLÍCITO: "me lembre…", "salva no Estudos…").
class Acao {
  final String tipo; // 'lembrete' | 'nota'
  final Map<String, String> params;
  final String original;
  const Acao(this.tipo, this.params, this.original);
}

/// Resultado da execução: texto limpo p/ exibir + confirmações p/ mostrar.
class ExecResult {
  final String texto;
  final List<String> confirmacoes;
  const ExecResult(this.texto, [this.confirmacoes = const []]);
}

typedef AgendarLembrete = Future<bool> Function(String texto, DateTime quando,
    {String? abrir, String? dizer});
typedef SalvarNota = Future<void> Function(String projeto, String texto);

/// Parser + executor das ações da Muse. Chamado SÓ sobre o reply FINAL
/// (nunca por frase do stream — o bloco poderia vir quebrado). Não lança:
/// bloco malformado é ignorado e falha de execução vira aviso textual.
class ChatActions {
  static const int maxPorResposta = 2;
  static const int maxTexto = 200;

  static final _reLinha = RegExp(
    r'\[\[ACAO\s*:\s*([A-Za-z]+)\s*((?:\|[^\[\]\n]*)*)\]\]',
    caseSensitive: false,
  );

  static final _reQuando = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})$',
  );

  /// Extrai as ações do reply (sem executar). Tipos desconhecidos e blocos
  /// quebrados são ignorados.
  static List<Acao> extrair(String reply) {
    final out = <Acao>[];
    for (final m in _reLinha.allMatches(reply)) {
      final tipo = m.group(1)!.toLowerCase();
      if (tipo != 'lembrete' && tipo != 'nota') continue;
      final params = <String, String>{};
      for (final parte in (m.group(2) ?? '').split('|')) {
        final i = parte.indexOf('=');
        if (i < 0) continue;
        final k = parte.substring(0, i).trim().toLowerCase();
        final v = parte.substring(i + 1).trim();
        if (k.isNotEmpty) params[k] = v;
      }
      out.add(Acao(tipo, params, m.group(0)!));
    }
    return out;
  }

  /// Tira os blocos do texto exibível (colapsa linhas em branco que sobrarem).
  static String limpar(String reply) {
    return reply
        .replaceAll(_reLinha, '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static DateTime? _parseQuando(String s) {
    final m = _reQuando.firstMatch(s.trim());
    if (m == null) return null;
    try {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _agendarPadrao(
      String texto, DateTime quando, String repete,
      {String? abrir, String? dizer}) async {
    final daqui = quando.difference(DateTime.now());
    final l = await LembretesService.instance.agendar(texto, daqui,
        recorrencia: repete, abrirMusePreset: abrir, abrirMusePergunta: dizer);
    return l != null;
  }

  /// Normaliza o `repete` do bloco de ação → 'none' | 'diario' | 'semanal'.
  static String _normRepete(String? s) {
    final v = (s ?? '').trim().toLowerCase();
    if (v.startsWith('dia') || v == 'daily') return 'diario';
    if (v.startsWith('sem') || v == 'weekly') return 'semanal';
    return 'none';
  }

  static const _dias = [
    'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'
  ];
  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static Future<void> _salvarPadrao(String projeto, String texto) =>
      Storage.instance.adicionarNotaEmProjeto(projeto, texto);

  /// Executa as ações do reply (até [maxPorResposta]). Com `completo: false`
  /// (parcial de stream que caiu no meio), só LIMPA sem executar — evita
  /// duplicar no fallback, que reenvia do zero e executa de novo.
  static Future<ExecResult> executarTodos(
    String reply, {
    bool completo = true,
    AgendarLembrete? agendar,
    SalvarNota? salvar,
  }) async {
    final acoes = extrair(reply);
    if (acoes.isEmpty || !completo) return ExecResult(limpar(reply));
    final confs = <String>[];
    for (final a in acoes.take(maxPorResposta)) {
      if (a.tipo == 'lembrete') {
        final texto = (a.params['texto'] ?? '').trim();
        final quando = _parseQuando(a.params['quando'] ?? '');
        if (texto.isEmpty || texto.length > maxTexto || quando == null) {
          continue;
        }
        if (quando.difference(DateTime.now()) <
            const Duration(minutes: 1)) {
          confs.add('⚠️ Não agendei: a data já passou.');
          continue;
        }
        // Alarme inteligente: `| abrir=coach|projetos|geral | dizer=<pergunta>` —
        // tocar abre a Muse naquele modo e já envia a pergunta. Inválido = ignora.
        var abrir = (a.params['abrir'] ?? '').trim().toLowerCase();
        if (!LembretesService.presetsMuseValidos.contains(abrir)) abrir = '';
        var dizer = (a.params['dizer'] ?? '').trim();
        if (dizer.length > maxTexto) dizer = '';
        final repete = _normRepete(a.params['repete']);
        try {
          // A recorrência e o abrir/dizer chegam ao serviço real pelo closure; o
          // executor injetado (testes) mantém a assinatura (texto, quando).
          final ok = await (agendar ??
                  (t, q, {abrir, dizer}) =>
                      _agendarPadrao(t, q, repete, abrir: abrir, dizer: dizer))(
              texto, quando,
              abrir: abrir.isEmpty ? null : abrir,
              dizer: dizer.isEmpty ? null : dizer);
          final abreTxt = dizer.isNotEmpty ? ' (abre a Muse e pergunta)' : '';
          final quandoTxt = repete == 'diario'
              ? 'repete todo dia ${_hhmm(quando)}'
              : repete == 'semanal'
                  ? 'repete toda ${_dias[quando.weekday - 1]} ${_hhmm(quando)}'
                  : quandoComDiaSemana(quando);
          confs.add(ok
              ? '⏰ Lembrete criado: $texto ($quandoTxt)$abreTxt'
              : '⚠️ Sem permissão de notificação: ative p/ agendar.');
        } catch (_) {
          confs.add('⚠️ Não consegui agendar agora. Tente de novo.');
        }
      } else if (a.tipo == 'nota') {
        final texto = (a.params['texto'] ?? '').trim();
        if (texto.isEmpty) continue;
        final projeto = (a.params['projeto'] ?? '').trim();
        try {
          await (salvar ?? _salvarPadrao)(
              projeto.isEmpty ? 'Estudos' : projeto, texto);
          confs.add(
              '📘 Salvo em ${projeto.isEmpty ? 'Estudos' : projeto}.');
        } catch (_) {
          confs.add('⚠️ Não consegui salvar agora. Tente de novo.');
        }
      }
    }
    return ExecResult(limpar(reply), confs);
  }
}
