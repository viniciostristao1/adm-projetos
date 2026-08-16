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
  String? comentario;
  List<NotaLink> links;

  /// Título centralizado da caixinha (campo próprio, acima do texto): o
  /// usuário seleciona uma palavra/frase no texto e toca em centralizar.
  String? titulo;

  Nota({
    required this.id,
    required this.texto,
    this.concluida = false,
    this.comentario,
    List<NotaLink>? links,
    this.titulo,
  }) : links = links ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'texto': texto,
        'concluida': concluida,
        if (comentario != null) 'comentario': comentario,
        if (titulo != null) 'titulo': titulo,
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

    return Nota(
      id: (j['id'] ?? '') as String,
      texto: normalizarTodos((j['texto'] ?? '') as String),
      concluida: (j['concluida'] ?? false) as bool,
      comentario: (j['link'] is String && (j['link'] as String).isNotEmpty)
          ? null
          : j['comentario'] as String?,
      links: lerLinks(),
      titulo: (j['titulo'] as String?)?.trim(),
    );
  }

  /// Garante que todo quadradinho ☐/☑ tenha o \uFE0E (VS15) logo depois —
  /// sem ele alguns celulares desenham o quadradinho como emoji colorido.
  /// Dados salvos antes do VS15 (backups antigos) são normalizados aqui.
  static String normalizarTodos(String texto) => texto.replaceAllMapped(
      RegExp('(☐|☑)\uFE0E?'), (m) => '${m.group(1)}\uFE0E');
}

/// Um projeto: nome + duas listas de caixas (tarefas atuais e ideias futuras).
class Projeto {
  String id;
  String nome;
  List<Nota> tarefas;
  List<Nota> futuro;

  /// Projeto em andamento (mostra ✓ verde no cartão da lista).
  bool emAndamento;

  Projeto({
    required this.id,
    required this.nome,
    List<Nota>? tarefas,
    List<Nota>? futuro,
    this.emAndamento = false,
  })  : tarefas = tarefas ?? [],
        futuro = futuro ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'tarefas': tarefas.map((n) => n.toJson()).toList(),
        'futuro': futuro.map((n) => n.toJson()).toList(),
        'emAndamento': emAndamento,
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
    );
  }
}