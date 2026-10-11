// Modelos do chat (isolados do resto do app).

/// Modo da conversa — define o "papel" da IA no servidor (system-prompt).
enum ChatPreset {
  livre('livre', 'Conversa', 'Discutir projetos e ideias'),
  coach('coach', 'Coach Calis', 'Treinador do Calis Timer (vê seu desempenho)');

  const ChatPreset(this.id, this.rotulo, this.descricao);
  final String id;
  final String rotulo;
  final String descricao;
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
