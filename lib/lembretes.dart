import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
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

/// Handler chamado quando o usuário toca num BOTÃO da notificação com o app em
/// BACKGROUND / fechado — roda num isolate próprio, por isso precisa ser
/// top-level e anotado com `@pragma('vm:entry-point')`.
@pragma('vm:entry-point')
void respostaNotificacaoBackground(NotificationResponse resposta) {
  LembretesService.reagendarPorAcao(resposta);
}

/// Handler com o app VIVO: reagenda e ainda atualiza a lista visível.
void _respostaNotificacaoForeground(NotificationResponse resposta) async {
  await LembretesService.reagendarPorAcao(resposta);
  await LembretesService.instance.recarregar();
}

/// Lembretes rápidos com NOTIFICAÇÃO LOCAL do Android.
///
/// Funciona 100% offline num APK: quem dispara é o AlarmManager do próprio
/// Android (não precisa de servidor nem de app aberto). O alarme é EXATO
/// (`exactAllowWhileIdle` + permissão `USE_EXACT_ALARM`, concedida
/// automaticamente a apps de lembrete) — dispara no minuto marcado mesmo com o
/// celular em repouso.
///
/// A própria notificação traz botões de REPROGRAMAR (30 min · 2 h · 24 h): ao
/// tocar num deles, o lembrete é reagendado sem abrir o app (mesmo fechado),
/// via [reagendarPorAcao] no handler de background.
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

  // ⚠️ id NOVO (v2): o Android CONGELA som/importância de um canal na criação —
  // mudar depois não pega. Trocamos o id para garantir som + prioridade máxima.
  static const String _canalId = 'lembretes_v2';
  static const String _canalIdAntigo = 'lembretes';
  static const String _canalNome = 'Lembretes';
  static const String _canalDesc = 'Lembretes rápidos do Taskix';
  static const String _chavePendentes = 'lembretes_pendentes_v1';
  static const String _chaveProxId = 'lembretes_prox_id_v1';

  /// Botões de reprogramar que aparecem na notificação (id, rótulo, duração).
  /// O Android mostra até ~3 botões — por isso três.
  static const List<(String, String, Duration)> _snoozes = [
    ('snooze_30', '30 min', Duration(minutes: 30)),
    ('snooze_120', '2 h', Duration(hours: 2)),
    ('snooze_1440', '24 h', Duration(hours: 24)),
  ];

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

  /// Detalhes da notificação COM os botões de reprogramar. Estático para o
  /// handler de background (outro isolate) montar igual ao do app.
  /// [texto] entra no `BigTextStyle` para o conteúdo escrito aparecer inteiro.
  static NotificationDetails _detalhes(String texto) {
    final corpo = texto.isEmpty ? 'Toque para abrir o Taskix' : texto;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _canalId,
        _canalNome,
        channelDescription: _canalDesc,
        importance: Importance.max,
        priority: Priority.max,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.reminder,
        icon: 'ic_notif',
        styleInformation: BigTextStyleInformation(corpo, contentTitle: corpo, summaryText: 'Taskix'),
        ticker: corpo,
        playSound: true,
        enableVibration: true,
        autoCancel: true,
        showWhen: true,
        ongoing: false,
        actions: [
          for (final s in _snoozes)
            AndroidNotificationAction(
              s.$1,
              s.$2,
              showsUserInterface: false,
              cancelNotification: true,
            ),
        ],
      ),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true, threadIdentifier: _canalId),
    );
  }

  static const AndroidNotificationChannel _canal = AndroidNotificationChannel(
    _canalId,
    _canalNome,
    description: _canalDesc,
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Instante do disparo = agora + [daqui], ARREDONDADO para BAIXO no minuto
  /// (segundos zerados) — assim toca no HH:MM que aparece em "AGENDADOS", não
  /// nos segundos seguintes (parecia ~1 min atrasada). Como [daqui] é sempre
  /// ≥ 1 min, o resultado nunca cai no passado. Retorna (local, tz UTC).
  static (DateTime, tz.TZDateTime) _quandoAgendar(Duration daqui) {
    final alvo = DateTime.now().add(daqui);
    final local =
        DateTime(alvo.year, alvo.month, alvo.day, alvo.hour, alvo.minute);
    final agendado = tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.UTC, local.millisecondsSinceEpoch);
    return (local, agendado);
  }

  /// Inicializa o plugin + timezone + canal. Chamado no `main()` (try/catch).
  Future<void> init() async {
    if (_pronto) return;
    tzdata.initializeTimeZones();
    const androidInit = AndroidInitializationSettings('ic_notif');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _respostaNotificacaoForeground,
      onDidReceiveBackgroundNotificationResponse:
          respostaNotificacaoBackground,
    );
    await _android?.createNotificationChannel(_canal);
    // Remove o canal antigo (importância high sem som garantido) para não
    // ficar duplicado nas configurações do Android.
    await _android?.deleteNotificationChannel(_canalIdAntigo);
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
    await prefs.reload(); // pega um contador de id atualizado por outro isolate
    final id = prefs.getInt(_chaveProxId) ?? 1;
    await prefs.setInt(_chaveProxId, id + 1);

    final (quando, agendado) = _quandoAgendar(daqui);

    await _plugin.zonedSchedule(
      id,
      'Lembrete',
      texto.isEmpty ? 'Toque para abrir o Taskix' : texto,
      agendado,
      _detalhes(texto),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: texto,
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

  /// Recarrega a lista a partir do disco e avisa a UI (usado após o snooze
  /// tocado com o app vivo).
  Future<void> recarregar() async {
    await _carregarPendentes();
    notifyListeners();
  }

  /// Reagenda um lembrete quando o usuário toca num BOTÃO da notificação.
  /// ESTÁTICO e autossuficiente: roda tanto no app vivo quanto no isolate de
  /// background (app fechado). Ignora toques que não sejam um dos [_snoozes].
  static Future<void> reagendarPorAcao(NotificationResponse resposta) async {
    final dur = _duracaoDaAcao(resposta.actionId);
    if (dur == null) return; // toque no corpo, não num botão de snooze

    // Isolate de background: garantir binding + plugins registrados.
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    tzdata.initializeTimeZones();

    final plugin = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('ic_notif');
    await plugin.initialize(
      const InitializationSettings(android: androidInit),
    );
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_canal);

    final texto = resposta.payload ?? '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final id = prefs.getInt(_chaveProxId) ?? 1;
    await prefs.setInt(_chaveProxId, id + 1);

    final (quando, agendado) = _quandoAgendar(dur);

    await plugin.zonedSchedule(
      id,
      'Lembrete',
      texto.isEmpty ? 'Toque para abrir o Taskix' : texto,
      agendado,
      _detalhes(texto),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: texto,
    );

    // Atualiza a lista persistida: tira o lembrete que disparou, põe o novo.
    await _mexerPendentesPrefs(
      prefs,
      removerId: resposta.id,
      adicionar: Lembrete(id: id, texto: texto, quando: quando),
    );
  }

  static Duration? _duracaoDaAcao(String? actionId) {
    if (actionId == null) return null;
    for (final s in _snoozes) {
      if (s.$1 == actionId) return s.$3;
    }
    return null;
  }

  Future<void> _carregarPendentes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // reload(): relê do disco. O snooze da notificação roda em OUTRO isolate
      // e grava direto no arquivo; sem o reload, o cache em memória deste
      // isolate ficaria velho e o lembrete reprogramado não apareceria.
      await prefs.reload();
      final raw = prefs.getString(_chavePendentes);
      _pendentes.clear();
      if (raw == null) return;
      final lista = (jsonDecode(raw) as List)
          .map((e) => Lembrete.fromJson(e as Map<String, dynamic>))
          .toList();
      _pendentes.addAll(lista);
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

  /// Edita a lista de pendentes DIRETO no disco (usado pelo snooze de
  /// background, que não tem acesso à lista em memória do app).
  static Future<void> _mexerPendentesPrefs(
    SharedPreferences prefs, {
    int? removerId,
    Lembrete? adicionar,
  }) async {
    var lista = <Lembrete>[];
    try {
      final raw = prefs.getString(_chavePendentes);
      if (raw != null) {
        lista = (jsonDecode(raw) as List)
            .map((e) => Lembrete.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    if (removerId != null) lista.removeWhere((l) => l.id == removerId);
    if (adicionar != null) lista.add(adicionar);
    try {
      await prefs.setString(
        _chavePendentes,
        jsonEncode(lista.map((l) => l.toJson()).toList()),
      );
    } catch (_) {}
  }
}
