// Modelos do chat (isolados do resto do app).

/// Força MAIÚSCULA no início de cada frase (começo do texto e após . ! ? : ou
/// quebra de linha + espaços). Não mexe em números/decimais (exige espaço após a
/// pontuação) nem em letras já maiúsculas. Aplicado no que o usuário envia.
String capitalizarFrases(String t) {
  if (t.isEmpty) return t;
  t = t.replaceFirstMapped(
      RegExp(r'^(\s*)(\p{Ll})', unicode: true),
      (m) => m[1]! + m[2]!.toUpperCase());
  return t.replaceAllMapped(
      RegExp(r'([.!?:]\s+|\n\s*)(\p{Ll})', unicode: true),
      (m) => m[1]! + m[2]!.toUpperCase());
}

/// Modo da conversa — define o "papel" da IA no servidor (system-prompt).
enum ChatPreset {
  livre('livre', 'Conversa', 'Discutir projetos e ideias'),
  coach('coach', 'Coach Calis', 'Treinador do Calis Timer (vê seu desempenho)');

  const ChatPreset(this.id, this.rotulo, this.descricao);
  final String id;
  final String rotulo;
  final String descricao;

  static ChatPreset deId(String? id) =>
      ChatPreset.values.firstWhere((p) => p.id == id, orElse: () => livre);
}

/// Uma mensagem da conversa.
class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String texto;
  final DateTime hora;

  const ChatMessage(this.role, this.texto, this.hora);

  ChatMessage.usuario(this.texto)
      : role = 'user',
        hora = DateTime.now();
  ChatMessage.ia(this.texto)
      : role = 'assistant',
        hora = DateTime.now();

  bool get ehUsuario => role == 'user';

  Map<String, dynamic> toJson() =>
      {'role': role, 'texto': texto, 'hora': hora.millisecondsSinceEpoch};

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        j['role'] as String? ?? 'assistant',
        j['texto'] as String? ?? '',
        DateTime.fromMillisecondsSinceEpoch((j['hora'] as num?)?.toInt() ?? 0),
      );
}

/// Uma conversa do Muse (histórico): tem título, modo (preset) e mensagens.
class Conversa {
  final String id;
  String titulo;
  ChatPreset preset;
  List<ChatMessage> mensagens;
  DateTime atualizadaEm;

  Conversa({
    required this.id,
    required this.titulo,
    required this.preset,
    required this.mensagens,
    required this.atualizadaEm,
  });

  factory Conversa.nova(ChatPreset preset) => Conversa(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        titulo: 'Nova conversa',
        preset: preset,
        mensagens: [],
        atualizadaEm: DateTime.now(),
      );

  bool get vazia => mensagens.isEmpty;

  /// Define o título a partir da 1ª mensagem do usuário (se ainda for o padrão).
  void talvezTitular() {
    if (titulo != 'Nova conversa') return;
    final primeira = mensagens.where((m) => m.ehUsuario).map((m) => m.texto);
    if (primeira.isEmpty) return;
    var t = primeira.first.replaceAll('\n', ' ').trim();
    if (t.length > 42) t = '${t.substring(0, 42)}…';
    if (t.isNotEmpty) titulo = t;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'preset': preset.id,
        'atualizadaEm': atualizadaEm.millisecondsSinceEpoch,
        'mensagens': mensagens.map((m) => m.toJson()).toList(),
      };

  factory Conversa.fromJson(Map<String, dynamic> j) => Conversa(
        id: j['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
        titulo: j['titulo'] as String? ?? 'Conversa',
        preset: ChatPreset.deId(j['preset'] as String?),
        atualizadaEm: DateTime.fromMillisecondsSinceEpoch(
            (j['atualizadaEm'] as num?)?.toInt() ?? 0),
        mensagens: ((j['mensagens'] as List?) ?? const [])
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
