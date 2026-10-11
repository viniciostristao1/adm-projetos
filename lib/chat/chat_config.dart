/// Configuração do recurso de CHAT (lida em tempo de COMPILAÇÃO via --dart-define).
///
/// Sem `CHAT=true` ou sem `TASKIX_CHAT_URL`, o recurso fica AUSENTE (o botão nem
/// aparece) — é assim que se gera um build "Play Store" sem o chat. NÃO há segredo
/// aqui: a autenticação é o ID token do Firebase do usuário logado (verificado no
/// servidor, que só aceita a conta do dono). Ver `lib/chat/` (módulo isolado).
class ChatConfig {
  static const bool _ligado = bool.fromEnvironment('CHAT', defaultValue: false);
  static const String url =
      String.fromEnvironment('TASKIX_CHAT_URL', defaultValue: '');

  /// O chat só existe se foi compilado com a flag E com a URL do proxy.
  static bool get habilitado => _ligado && url.isNotEmpty;
}
