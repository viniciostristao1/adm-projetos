// Modelos: Projeto e Nota (caixa de texto), com serialização JSON.

/// Uma caixa de texto dentro de um projeto (minha ideia anotada).
class Nota {
  String id;
  String texto;
  bool concluida;
  String? comentario;
  String? link;

  Nota({
    required this.id,
    required this.texto,
    this.concluida = false,
    this.comentario,
    this.link,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'texto': texto,
        'concluida': concluida,
        if (comentario != null) 'comentario': comentario,
        if (link != null) 'link': link,
      };

  factory Nota.fromJson(Map<String, dynamic> j) => Nota(
        id: (j['id'] ?? '') as String,
        texto: normalizarTodos((j['texto'] ?? '') as String),
        concluida: (j['concluida'] ?? false) as bool,
        comentario: j['comentario'] as String?,
        link: j['link'] as String?,
      );

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