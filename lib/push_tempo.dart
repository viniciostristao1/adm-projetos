import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'chat/chat_config.dart';
import 'lembretes.dart';

/// Push da previsão do tempo (6:15) vindo do SERVIDOR (FCM).
///
/// Por quê: o alarme LOCAL das 6:15 não dispara em alguns Androids (bug
/// específico do caminho local da previsão; os lembretes comuns, mesmo motor,
/// funcionam). O push do servidor ignora Doze/OEM e o caminho local — o Android
/// exibe a notificação mesmo com o app FECHADO, no canal próprio
/// `tempo_push_v1`. O envio é disparado por um cron na VPS às 6:15 (exceto
/// domingo). O alarme local continua como reserva (quem funcionar, funciona).
///
/// TOQUE: abre a Muse num papo sobre o tempo (reusa o bridge de "alarme
/// inteligente" do [LembretesService]: `geral` + pergunta → o proxy injeta a
/// previsão quando perguntada). Três estados:
/// - 1º plano: `onMessage` mostra uma notificação local com payload Muse; tocar
///   cai no handler do flutter_local_notifications (avisarPedidoMuse).
/// - 2º plano (app vivo): `onMessageOpenedApp` → avisarPedidoMuse (listener vivo).
/// - app morto: `getInitialMessage` (via [consumirToqueInicial], ANTES do runApp)
///   → salvarPedidoMuse no disco; a ProjetosScreen consome no initState.
///
/// Tudo best-effort: nenhuma falha de rede/login derruba o app.
class PushTempo {
  static const String canalId = 'tempo_push_v1';
  static const int _idForeground = 910200; // fora das faixas do alarme local

  // Abre a Muse em modo Geral perguntando a previsão (o proxy injeta o tempo
  // sob pergunta explícita). Preset tem de estar em `presetsMuseValidos`.
  static const String _presetTempo = 'geral';
  static const String _perguntaTempo =
      'Como está a previsão do tempo hoje em Lajeado?';

  static final FlutterLocalNotificationsPlugin _fln =
      FlutterLocalNotificationsPlugin();

  static String? _ultimoToken;

  static const AndroidNotificationChannel _canal = AndroidNotificationChannel(
    canalId,
    'Previsão do tempo',
    description: 'Previsão de Lajeado às 6:15 (push do servidor)',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  /// Consome um toque que ABRIU o app a partir de MORTO (push na bandeja).
  /// Chamar no `main()` com AWAIT, ANTES do runApp, p/ a ProjetosScreen achar
  /// o pedido no disco (`lerEConsumirPedidoMuse`) já no initState. Rápido
  /// (só um canal de plataforma). Best-effort.
  static Future<void> consumirToqueInicial() async {
    if (!ChatConfig.habilitado) return;
    try {
      final inicial = await FirebaseMessaging.instance.getInitialMessage();
      if (_ehTempo(inicial)) {
        await LembretesService.salvarPedidoMuse(_presetTempo, _perguntaTempo);
      }
    } catch (_) {}
  }

  /// Cria o canal, pede permissão, registra o token no servidor e escuta
  /// mensagens/toques. Chamar no `main()` após o Firebase iniciar (fire-and-
  /// forget — faz rede).
  static Future<void> init() async {
    if (!ChatConfig.habilitado) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      // O sistema usa ESTE canal ao exibir o push com o app fechado.
      await _fln
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_canal);
      // Em 1º plano o FCM não exibe sozinho → mostramos uma notificação local.
      FirebaseMessaging.onMessage.listen(_mostrarEmPrimeiroPlano);
      // Toque com o app em 2º plano (vivo): abre a Muse via listener da UI.
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        if (_ehTempo(m)) {
          LembretesService.instance
              .avisarPedidoMuse(_presetTempo, _perguntaTempo);
        }
      });
      // Token: registra agora e a cada renovação.
      fm.onTokenRefresh.listen((t) {
        _ultimoToken = t;
        _registrar(t);
      });
      final token = await fm.getToken();
      if (token != null) {
        _ultimoToken = token;
        await _registrar(token);
      }
      // Cold start pode logar DEPOIS do getToken: re-registra quando o usuário
      // ficar disponível.
      FirebaseAuth.instance.authStateChanges().listen((u) {
        if (u != null && _ultimoToken != null) _registrar(_ultimoToken!);
      });
    } catch (_) {
      // best-effort: sem push, o alarme local (reserva) segue valendo.
    }
  }

  static bool _ehTempo(RemoteMessage? m) =>
      m != null && (m.data['tipo'] ?? '') == 'tempo';

  static Future<void> _mostrarEmPrimeiroPlano(RemoteMessage m) async {
    if (!_ehTempo(m)) return;
    try {
      final n = m.notification;
      final titulo = n?.title ?? 'Previsão do tempo';
      final corpo = n?.body ?? '';
      await _fln.show(
        _idForeground,
        titulo,
        corpo,
        NotificationDetails(
          android: AndroidNotificationDetails(
            canalId,
            'Previsão do tempo',
            channelDescription: 'Previsão de Lajeado às 6:15 (push do servidor)',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_tempo',
            styleInformation: BigTextStyleInformation(corpo,
                contentTitle: titulo, summaryText: 'Tempo · Lajeado'),
          ),
        ),
        // Tocar abre a Muse perguntando a previsão (mesmo bridge dos lembretes).
        payload: LembretesService.payloadMuse(_presetTempo, _perguntaTempo),
      );
    } catch (_) {}
  }

  static Future<void> _registrar(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idt = (await user.getIdToken()) ?? '';
      if (idt.isEmpty) return;
      await http
          .post(
            Uri.parse('${ChatConfig.url}/registrar_push'),
            headers: {
              'Authorization': 'Bearer $idt',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }
}
