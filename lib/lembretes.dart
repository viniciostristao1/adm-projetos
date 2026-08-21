import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Um lembrete agendado (para exibir/cancelar na lista de pendentes).
class Lembrete {
  Lembrete({required this.id, required this.texto, required this.quando});

  final int id;
  final String texto;
  final DateTime quando;

  Map<String, dynamic> toJson() => {
        'id': id,
        'texto': texto,
        'quando': quando.millisecondsSinceEpoch,
      };

  factory Lembrete.fromJson(Map<String, dynamic> j) => Lembrete(
        id: j['id'] as int,
        texto: j['texto'] as String,
        quando: DateTime.fromMillisecondsSinceEpoch(j['quando'] as int),
      );
}

/// Lembretes rápidos com NOTIFICAÇÃO LOCAL do Android.
///
/// Funciona 100% offline num APK: quem dispara é o AlarmManager do próprio
/// Android (não precisa de servidor nem de app aberto). O alarme é EXATO
/// (`exactAllowWhileIdle` + permissão `USE_EXACT_ALARM`, concedida
/// automaticamente a apps de lembrete) — dispara no minuto marcado mesmo com o
/// celular em repouso.
///
/// Guarda a lista de pendentes em SharedPreferences só para EXIBIR (texto +
/// horário) e permitir cancelar; a fonte de verdade do agendamento é o próprio
/// sistema.
class LembretesService extends ChangeNotifier {
  LembretesService._();
  static final LembretesService instance = LembretesService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _pronto = false;
  bool get pronto => _pronto;

  static const String _canalId = 'lembretes';
  static const String _canalNome = 'Lembretes';
  static const String _canalDesc = 'Lembretes rápidos do Taskix';
  static const String _chavePendentes = 'lembretes_pendentes_v1';
  static const String _chaveProxId = 'lembretes_prox_id_v1';

  final List<Lembrete> _pendentes = [];

  /// Lembretes ainda por vir (ordenados por horário; os vencidos somem).
  List<Lembrete> get pendentes {
    final agora = DateTime.now();
    final vivos = _pendentes.where((l) => l.quando.isAfter(agora)).toList()
      ..sort((a, b) => a.quando.compareTo(b.quando));
    return vivos;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Inicializa o plugin + timezone + canal. Chamado no `main()` (try/catch).
  Future<void> init() async {
    if (_pronto) return;
    tzdata.initializeTimeZones();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);
    await _android?.createNotificationChannel(const AndroidNotificationChannel(
      _canalId,
      _canalNome,
      description: _canalDesc,
      importance: Importance.high,
    ));
    await _carregarPendentes();
    _pronto = true;
  }

  /// Pede a permissão de notificação (Android 13+). Retorna true se concedida
  /// (ou se não é aplicável). Chamado antes de agendar o primeiro lembrete.
  Future<bool> pedirPermissao() async {
    final a = _android;
    if (a == null) return true;
    final ok = await a.requestNotificationsPermission();
    return ok ?? true;
  }

  /// Agenda um lembrete para daqui a [daqui]. Retorna o [Lembrete] criado, ou
  /// null se a permissão foi negada.
  Future<Lembrete?> agendar(String texto, Duration daqui) async {
    if (!_pronto) await init();
    if (!await pedirPermissao()) return null;

    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_chaveProxId) ?? 1;
    await prefs.setInt(_chaveProxId, id + 1);

    final quando = DateTime.now().add(daqui);
    // Instante ABSOLUTO = agora + duração. Como o lembrete é relativo, computar
    // em UTC dá o mesmo instante independentemente do fuso do aparelho.
    final agendado = tz.TZDateTime.now(tz.UTC).add(daqui);

    const detalhes = NotificationDetails(
      android: AndroidNotificationDetails(
        _canalId,
        _canalNome,
        channelDescription: _canalDesc,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _plugin.zonedSchedule(
      id,
      'Lembrete',
      texto.isEmpty ? 'Toque para abrir o Taskix' : texto,
      agendado,
      detalhes,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );

    final l = Lembrete(id: id, texto: texto, quando: quando);
    _pendentes.add(l);
    await _salvarPendentes();
    notifyListeners();
    return l;
  }

  /// Cancela um lembrete agendado.
  Future<void> cancelar(int id) async {
    await _plugin.cancel(id);
    _pendentes.removeWhere((l) => l.id == id);
    await _salvarPendentes();
    notifyListeners();
  }

  Future<void> _carregarPendentes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_chavePendentes);
      if (raw == null) return;
      final lista = (jsonDecode(raw) as List)
          .map((e) => Lembrete.fromJson(e as Map<String, dynamic>))
          .toList();
      _pendentes
        ..clear()
        ..addAll(lista);
      // Poda os que já venceram desde a última sessão.
      final agora = DateTime.now();
      final antes = _pendentes.length;
      _pendentes.removeWhere((l) => !l.quando.isAfter(agora));
      if (_pendentes.length != antes) await _salvarPendentes();
    } catch (_) {}
  }

  Future<void> _salvarPendentes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _chavePendentes,
        jsonEncode(_pendentes.map((l) => l.toJson()).toList()),
      );
    } catch (_) {}
  }
}
