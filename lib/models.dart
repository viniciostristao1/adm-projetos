// Modelos: Projeto e Nota (caixa de texto), com serialização JSON.

/// Uma caixa de texto dentro de um projeto (minha ideia anotada).
class Nota {
  String id;
  String texto;

  Nota({required this.id, required this.texto});

  Map<String, dynamic> toJson() => {'id': id, 'texto': texto};

  factory Nota.fromJson(Map<String, dynamic> j) => Nota(
        id: (j['id'] ?? '') as String,
        texto: (j['texto'] ?? '') as String,
      );
}

/// Um projeto: nome + duas listas de caixas (tarefas atuais e ideias futuras).
class Projeto {
  String id;
  String nome;
  List<Nota> tarefas;
  List<Nota> futuro;

  Projeto({
    required this.id,
    required this.nome,
    List<Nota>? tarefas,
    List<Nota>? futuro,
  })  : tarefas = tarefas ?? [],
        futuro = futuro ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'tarefas': tarefas.map((n) => n.toJson()).toList(),
        'futuro': futuro.map((n) => n.toJson()).toList(),
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
    );
  }
}