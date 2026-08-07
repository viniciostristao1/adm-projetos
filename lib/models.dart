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

/// Um projeto: nome + lista de caixas de texto.
class Projeto {
  String id;
  String nome;
  List<Nota> notas;

  Projeto({required this.id, required this.nome, List<Nota>? notas})
      : notas = notas ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'notas': notas.map((n) => n.toJson()).toList(),
      };

  factory Projeto.fromJson(Map<String, dynamic> j) => Projeto(
        id: (j['id'] ?? '') as String,
        nome: (j['nome'] ?? '') as String,
        notas: ((j['notas'] ?? []) as List)
            .map((e) => Nota.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}