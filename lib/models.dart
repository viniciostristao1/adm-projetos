// Modelos: Projeto e Nota (caixa de texto), com serialização JSON.

/// Um link da caixinha (até 3). O título (ex.: do YouTube) é buscado via
/// oEmbed e salvo AQUI — assim aparece nos comentários mesmo depois de
/// fechar e reabrir o projeto.
class NotaLink {
  String url;
  String? titulo;

  NotaLink({required this.url, this.titulo});

  Map<String, dynamic> toJson() => {
        'url': url,
        if (titulo != null) 'titulo': titulo,
      };

  factory NotaLink.fromJson(Map<String, dynamic> j) => NotaLink(
        url: (j['url'] ?? '') as String,
        titulo: j['titulo'] as String?,
      );
}

/// Uma caixa de texto dentro de um projeto (minha ideia anotada).
class Nota {
  String id;
  String texto;
  bool concluida;

  /// Caixinha minimizada (botão "•••" da barra): o conteúdo aparece só nas
  /// 3 primeiras linhas, com reticências na 3ª. Estado por caixinha, salvo
  /// junto com o resto (backward-compatible: ausente no JSON = false).
  bool minimizada;

  String? comentario;
  List<NotaLink> links;

  Nota({
    required this.id,
    required this.texto,
    this.concluida = false,
    this.minimizada = false,
    this.comentario,
    List<NotaLink>? links,
  }) : links = links ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'texto': texto,
        'concluida': concluida,
        if (minimizada) 'minimizada': true,
        if (comentario != null) 'comentario': comentario,
        'links': links.map((l) => l.toJson()).toList(),
      };

  factory Nota.fromJson(Map<String, dynamic> j) {
    List<NotaLink> lerLinks() {
      final ls = j['links'];
      if (ls is List && ls.isNotEmpty) {
        return ls.map((e) => NotaLink.fromJson(e as Map<String, dynamic>)).toList();
      }
      // Dados antigos: um único campo "link" (e o título do YouTube ficava
      // no "comentario"). Migra movendo o título para o link e limpando o
      // comentário (que era só o eco do título).
      final antigo = j['link'] as String?;
      if (antigo != null && antigo.isNotEmpty) {
        final titulo = (j['comentario'] as String?)?.trim();
        return [
          NotaLink(
            url: antigo,
            titulo: (titulo == null || titulo.isEmpty) ? null : titulo,
          ),
        ];
      }
      return [];
    }

    // Dados da versão com "título centralizado" (campo próprio): o título
    // volta para o INÍCIO do texto — agora a centralização é por linha.
    final tituloAntigo = (j['titulo'] as String?)?.trim();
    final textoBase = normalizarTodos((j['texto'] ?? '') as String);
    final texto =
        (tituloAntigo == null || tituloAntigo.isEmpty)
            ? textoBase
            : (textoBase.isEmpty ? tituloAntigo : '$tituloAntigo\n$textoBase');

    return Nota(
      id: (j['id'] ?? '') as String,
      texto: texto,
      concluida: (j['concluida'] ?? false) as bool,
      minimizada: (j['minimizada'] ?? false) as bool,
      comentario: (j['link'] is String && (j['link'] as String).isNotEmpty)
          ? null
          : j['comentario'] as String?,
      links: lerLinks(),
    );
  }

  /// Garante que todo quadradinho ☐/☑ tenha o \uFE0E (VS15) logo depois —
  /// sem ele alguns celulares desenham o quadradinho como emoji colorido.
  /// Dados salvos antes do VS15 (backups antigos) são normalizados aqui.
  static String normalizarTodos(String texto) => texto.replaceAllMapped(
      RegExp('(☐|☑)\uFE0E?'), (m) => '${m.group(1)}\uFE0E');
}

class AbaExtra {
  String id;
  String nome;
  List<Nota> notas;

  AbaExtra({required this.id, required this.nome, List<Nota>? notas})
      : notas = notas ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'notas': notas.map((n) => n.toJson()).toList(),
      };

  factory AbaExtra.fromJson(Map<String, dynamic> j) => AbaExtra(
        id: (j['id'] ?? '') as String,
        nome: (j['nome'] as String?)?.trim().isNotEmpty == true
            ? (j['nome'] as String).trim()
            : 'Nova aba',
        notas: ((j['notas'] ?? []) as List)
            .map((e) => Nota.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Um projeto: nome + duas listas de caixas (tarefas atuais e ideias futuras).
class Projeto {
  String id;
  String nome;
  List<Nota> tarefas;
  List<Nota> futuro;

  /// Projeto em andamento (mostra ✓ verde no cartão da lista).
  bool emAndamento;

  /// Cor escolhida para a pasta quando NÃO está em andamento (null = sem cor).
  /// Valores: azul, amarelo, vermelho, verde, roxo, marrom, bege.
  String? cor;

  String? nomeTarefas;
  String? nomeFuturo;
  List<AbaExtra> abasExtras;

  String get nomeTarefasEff {
    final v = nomeTarefas?.trim();
    return v != null && v.isNotEmpty ? v : 'Tarefas';
  }

  String get nomeFuturoEff {
    final v = nomeFuturo?.trim();
    return v != null && v.isNotEmpty ? v : 'Ideias';
  }

  String nomeAba(int i) {
    if (i == 0) return nomeTarefasEff;
    if (i == 1) return nomeFuturoEff;
    final idx = i - 2;
    if (idx >= 0 && idx < abasExtras.length) return abasExtras[idx].nome;
    return 'Aba';
  }

  List<Nota> notasDaAba(int i) {
    if (i == 0) return tarefas;
    if (i == 1) return futuro;
    return abasExtras[i - 2].notas;
  }

  int get qtdAbas => 2 + abasExtras.length;

  Projeto({
    required this.id,
    required this.nome,
    List<Nota>? tarefas,
    List<Nota>? futuro,
    this.emAndamento = false,
    this.cor,
    this.nomeTarefas,
    this.nomeFuturo,
    List<AbaExtra>? abasExtras,
  })  : tarefas = tarefas ?? [],
        futuro = futuro ?? [],
        abasExtras = abasExtras ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'tarefas': tarefas.map((n) => n.toJson()).toList(),
        'futuro': futuro.map((n) => n.toJson()).toList(),
        'emAndamento': emAndamento,
        if (cor != null) 'cor': cor,
        if (nomeTarefas != null && nomeTarefas!.trim().isNotEmpty)
          'nomeTarefas': nomeTarefas!.trim(),
        if (nomeFuturo != null && nomeFuturo!.trim().isNotEmpty)
          'nomeFuturo': nomeFuturo!.trim(),
        if (abasExtras.isNotEmpty)
          'abasExtras': abasExtras.map((a) => a.toJson()).toList(),
      };

  factory Projeto.fromJson(Map<String, dynamic> j) {
    List<Nota> ler(String chave) => ((j[chave] ?? []) as List)
        .map((e) => Nota.fromJson(e as Map<String, dynamic>))
        .toList();

    final velhas = ler('notas'); // dados antigos (antes das abas)

    return Projeto(
      id: (j['id'] ?? '') as String,
      nome: (j['nome'] ?? '') as String,
      tarefas: ler('tarefas').isNotEmpty ? ler('tarefas') : velhas,
      futuro: ler('futuro'),
      emAndamento: (j['emAndamento'] ?? false) as bool,
      cor: j['cor'] as String?,
      nomeTarefas: j['nomeTarefas'] as String?,
      nomeFuturo: j['nomeFuturo'] as String?,
      abasExtras: ((j['abasExtras'] ?? []) as List)
          .map((e) => AbaExtra.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}