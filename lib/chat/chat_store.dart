import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'chat_models.dart';

/// Histórico LOCAL das conversas do Muse. Chave PRÓPRIA no SharedPreferences —
/// NÃO toca no `Storage` dos projetos nem na cadeia de proteção do AGENTS.md.
///
/// ⚠️ PROTEÇÃO CONTRA PERDA (duas camadas, complementares):
///  1. NO APP (aqui): fila FIFO + leitura estrita + MERGE que nunca encolhe
///     (V0.1.118) — defende de saves concorrentes / foto atrasada.
///  2. NO ANDROID (V0.1.119): o `FlutterSharedPreferences.xml` está EXCLUÍDO do
///     Auto Backup do Google (ver `android/.../xml/backup_rules.xml` e
///     `data_extraction_rules.xml`). Sem isso, um restore de snapshot ANTIGO
///     (reinstalar / trocar de aparelho / auto-restaurar) trocava o arquivo
///     inteiro embaixo do app e as conversas voltavam para um dia passado — o
///     merge da camada 1 não alcança isso (o SO substitui o arquivo, não as
///     mensagens). Os projetos NÃO dependem disto (ficam em arquivos próprios).
class ChatStore {
  static const _chave = 'taskix_muse_convs_v1';
  static const _chaveAntiga = 'taskix_chat_v1'; // conversa única (pré-histórico)
  static const _chaveUltima = 'taskix_muse_ultima_v1'; // id da última conversa ativa
  static const _maxConversas = 60;
  static const _maxMsgs = 120; // por conversa

  /// Fila FIFO de gravações: `salvar`/`remover` encadeiam aqui para nunca haver
  /// dois read-modify-write concorrentes (o 2º lia antes do 1º gravar e o 1º,
  /// mais lento, sobrescrevia o mais novo = mensagens sumindo ao sair/voltar).
  static Future<void> _fila = Future.value();

  /// Cache em memória da última decodificação de `listar()`, VALIDADO pelo string
  /// bruto salvo (`_cacheStr`): se o disco não mudou desde a última leitura, não
  /// redecodifica. É só de LEITURA (UI) — os GRAVADORES NUNCA usam o cache (leem
  /// o disco via `_listarInterno`, fonte da verdade do merge anti-perda). Como a
  /// validação é por conteúdo do string, os testes seguem isolados (cada
  /// `setMockInitialValues` muda o string → redecodifica).
  static List<Conversa>? _cache;
  static String? _cacheStr;

  /// Pré-carrega o histórico (e inicializa o SharedPreferences) em 2º plano, para
  /// a 1ª abertura do Muse não piscar ~1s na tela de loading enquanto lê o disco.
  /// Fire-and-forget no start do app (`ProjetosScreen`), só com o chat habilitado.
  static Future<void> aquecer() => listar();

  /// Espera a fila esvaziar (usado em testes).
  static Future<void> sincronizar() => _fila;

  /// Marca/ lê qual foi a última conversa aberta (para reabrir a MESMA ao voltar).
  static Future<void> marcarUltima(String id) async {
    try {
      (await SharedPreferences.getInstance()).setString(_chaveUltima, id);
    } catch (_) {}
  }

  static Future<String?> ultimaId() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_chaveUltima);
    } catch (_) {
      return null;
    }
  }

  /// Todas as conversas, mais recentes primeiro. Migra a conversa antiga (única)
  /// para uma Conversa na 1ª vez, para não perder o chat atual.
  static Future<List<Conversa>> listar() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_chave);
      if (s != null && s.isNotEmpty) {
        // Disco inalterado desde a última leitura → devolve o cache (sem redecodificar).
        if (_cache != null && s == _cacheStr) return _cache!;
        final list = (jsonDecode(s) as List)
            .map((e) => Conversa.fromJson(e as Map<String, dynamic>))
            .toList();
        list.sort((a, b) => b.atualizadaEm.compareTo(a.atualizadaEm));
        _cacheStr = s;
        _cache = list;
        return list;
      }
      // migração do formato antigo
      final antiga = p.getString(_chaveAntiga);
      if (antiga != null && antiga.isNotEmpty) {
        final msgs = (jsonDecode(antiga) as List)
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        if (msgs.isNotEmpty) {
          final c = Conversa(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            titulo: 'Conversa anterior',
            preset: ChatPreset.projetos,
            mensagens: msgs,
            atualizadaEm: msgs.last.hora,
          )..talvezTitular();
          await _gravar([c]);
          await p.remove(_chaveAntiga);
          return [c];
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Insere/atualiza a conversa (upsert). Fotografa o estado NA HORA da chamada
  /// e aplica na fila, em ordem: o último estado fotografado sempre vence —
  /// sair da tela e voltar em segundos não perde mais mensagens.
  static Future<void> salvar(Conversa conv) {
    // Deep-copy via JSON para desgrudar do objeto vivo (que continua mutando
    // enquanto a fila anda).
    final foto = Conversa.fromJson(conv.toJson());
    foto.atualizadaEm = DateTime.now();
    _fila = _fila.then((_) async {
      try {
        final todas = await _listarInterno(); // LANÇA se corrompido -> aborta (não apaga)
        final idx = todas.indexWhere((c) => c.id == foto.id);
        if (idx >= 0) {
          // NUNCA ENCOLHER: a foto da tela pode estar ATRASADA em relação ao que já
          // está salvo (ex.: resposta anexada em background via `anexarIa`, ou a tela
          // recarregada de um disco já defasado). Então MESCLA (união de mensagens,
          // sem perder nenhuma de nenhum lado) em vez de sobrescrever. Era a causa de
          // "sumiu o que escrevi hoje" — uma foto velha apagava o recente (V0.1.118).
          foto.mensagens = _mesclarMensagens(todas[idx].mensagens, foto.mensagens);
          todas.removeAt(idx);
        }
        if (foto.mensagens.length > _maxMsgs) {
          foto.mensagens = foto.mensagens.sublist(foto.mensagens.length - _maxMsgs);
        }
        todas.insert(0, foto);
        await _gravar(todas);
      } catch (_) {
        // leitura corrompida/indisponível: NÃO grava (preserva o que há no disco).
      }
    });
    return _fila;
  }

  /// Lê as conversas SEM tolerar corrupção (usado pelos GRAVADORES): se o JSON
  /// salvo estiver corrompido/ilegível, LANÇA — e quem grava aborta, nunca
  /// sobrescrevendo o disco com MENOS dados. A `listar()` pública é tolerante
  /// (devolve [] em erro) só para a UI não travar; gravar com [] apagaria tudo.
  static Future<List<Conversa>> _listarInterno() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_chave);
    if (s == null || s.isEmpty) return <Conversa>[];
    final list = (jsonDecode(s) as List)
        .map((e) => Conversa.fromJson(e as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.atualizadaEm.compareTo(a.atualizadaEm));
    return list;
  }

  /// União de mensagens que NUNCA perde nenhuma: junta `salvas` + `foto` (chave =
  /// role|hora|texto) e REORDENA por hora (cronológico). Resolve o caso de uma foto
  /// atrasada tentar encolher E o bug de ORDENAÇÃO (V0.1.182): antes os extras da
  /// foto iam pro FIM da lista — uma mensagem de DIAS atrás (resposta nunca entregue,
  /// corte de 120 msgs, save defasado) podia reaparecer como a ÚLTIMA e o modelo
  /// respondia a ela como se fosse recente. Só reordena se TODAS têm carimbo válido
  /// (>0); conversas legadas sem `hora` ficam na ordem de união (sem bagunçar).
  static List<ChatMessage> _mesclarMensagens(
      List<ChatMessage> salvas, List<ChatMessage> foto) {
    String chave(ChatMessage m) =>
        '${m.role}|${m.hora.millisecondsSinceEpoch}|${m.texto}';
    final vistos = <String>{};
    final out = <ChatMessage>[];
    for (final m in salvas) {
      if (vistos.add(chave(m))) out.add(m);
    }
    for (final m in foto) {
      if (vistos.add(chave(m))) out.add(m);
    }
    if (out.every((m) => m.hora.millisecondsSinceEpoch > 0)) {
      // Sort ESTÁVEL por hora (índice de união como desempate — Dart não garante
      // estabilidade): mensagens do mesmo instante mantêm a ordem de inserção.
      final pares = [for (var i = 0; i < out.length; i++) (i, out[i])];
      pares.sort((a, b) {
        final c = a.$2.hora.compareTo(b.$2.hora);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
      return [for (final p in pares) p.$2];
    }
    return out;
  }

  /// Uma conversa pelo id (ou null). Usado p/ recarregar a tela a partir do
  /// store (fonte da verdade da resposta que chegou em background).
  static Future<Conversa?> porId(String id) async {
    try {
      final todas = await listar();
      for (final c in todas) {
        if (c.id == id) return c;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Anexa a resposta da IA na conversa (pela fila — mesma proteção do
  /// `salvar`). É assim que a resposta SOBREVIVE ao botão voltar: o envio em
  /// background grava aqui mesmo sem tela montada; ao voltar, a tela recarrega
  /// de lá (`porId`) ou reanexa ao futuro em voo (`ChatService.pendenteDe`).
  static Future<void> anexarIa(String id, String reply) {
    _fila = _fila.then((_) async {
      try {
        final todas = await _listarInterno();
        final i = todas.indexWhere((c) => c.id == id);
        if (i < 0) return;
        final c = todas[i];
        c.mensagens = [...c.mensagens, ChatMessage.ia(reply)];
        if (c.mensagens.length > _maxMsgs) {
          c.mensagens = c.mensagens.sublist(c.mensagens.length - _maxMsgs);
        }
        c.atualizadaEm = DateTime.now();
        todas.removeAt(i);
        todas.insert(0, c);
        await _gravar(todas);
      } catch (_) {}
    });
    return _fila;
  }

  static Future<void> remover(String id) {
    _fila = _fila.then((_) async {
      try {
        final todas = await _listarInterno()
          ..removeWhere((c) => c.id == id);
        await _gravar(todas);
      } catch (_) {}
    });
    return _fila;
  }

  static Future<void> _gravar(List<Conversa> todas) async {
    final p = await SharedPreferences.getInstance();
    final corte = todas.length > _maxConversas
        ? todas.sublist(0, _maxConversas)
        : todas;
    final str = jsonEncode(corte.map((c) => c.toJson()).toList());
    await p.setString(_chave, str);
    // Mantém o cache coerente com o disco: a próxima `listar()` não redecodifica.
    _cacheStr = str;
    _cache = List<Conversa>.of(corte);
  }
}
