import 'dart:ui' show DartPluginRegistrant;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'chat/chat_service.dart';
import 'lembretes.dart';

/// Atualização de madrugada da previsão do tempo (V0.1.194).
///
/// O alarme das 6:15 guarda o texto no agendamento — sem isto, ele tocaria com
/// o conteúdo do último app-open (podendo amanhecer defasado). Um alarme exato
/// às 05:30 busca previsão + notícia frescas no servidor e REESCREVE os slots
/// das 6:15; no fim, encadeia o próximo 05:30 (auto-perpétuo, sobrevive sem
/// abrir o app; o plugin reagenda no boot). Se o toggle estiver desligado, o
/// encadeamento para (cancela o refresh).

/// Id próprio, fora da faixa dos slots (910000–910002) e do backup (900001).
const int idRefreshMadrugada = 910100;
const int horaRefresh = 5;
const int minRefresh = 30;

/// ⛔ Reserva LOCAL da previsão (alarme 05:30 que reagenda os 6:15 locais)
/// DESLIGADA na V0.1.224: o PUSH do servidor (FCM) é a fonte ÚNICA e confiável;
/// com o alarme local TAMBÉM disparando, o dono recebia DUAS notificações iguais.
/// Com `false`, o `armarRefreshMadrugada` e o callback CANCELAM a si mesmos e os
/// slots locais (via `agendarPrevisaoTempo`). Reativar só se o FCM sair de cena.
const bool reservaTempoLocalAtiva = false;

/// Um slot 6:15 calculado (puro, testável): ordem, textos e instante local.
typedef SlotTempo = ({
  int slot,
  String titulo,
  String corpo,
  DateTime quandoLocal,
});

String _iso(DateTime b) =>
    '${b.year.toString().padLeft(4, '0')}-'
    '${b.month.toString().padLeft(2, '0')}-'
    '${b.day.toString().padLeft(2, '0')}';

/// Próximo 05:30 local (hoje se ainda falta, senão amanhã). Puro, testável.
DateTime proximaMadrugada(DateTime agora) {
  var alvo = DateTime(agora.year, agora.month, agora.day, horaRefresh, minRefresh);
  if (!alvo.isAfter(agora)) alvo = alvo.add(const Duration(days: 1));
  return alvo;
}

/// Slots 6:15 a partir dos dias do servidor. Puro, testável (máx. 3, pula
/// domingo, pula 6:15 de hoje já passada, ignora dia sem dado). Mesma regra do
/// `LembretesService.agendarPrevisaoTempo` — as duas usam ESTA função.
List<SlotTempo> calcularSlotsTempo(
    List<Map<String, String>> dias, DateTime agora) {
  final porData = {for (final d in dias) (d['data'] ?? ''): d};
  final out = <SlotTempo>[];
  var slot = 0;
  for (var off = 0;
      off < 12 && slot < LembretesService.tempoSlots;
      off++) {
    final base = DateTime(agora.year, agora.month, agora.day + off);
    if (base.weekday == DateTime.sunday) continue; // pula domingo
    final quando = DateTime(base.year, base.month, base.day,
        LembretesService.tempoHora, LembretesService.tempoMin);
    if (!quando.isAfter(agora)) continue; // 6:15 de hoje já passou
    final msg = porData[_iso(base)];
    if (msg == null) continue; // sem dado p/ esse dia
    final titulo =
        (msg['titulo'] ?? '').isEmpty ? 'Previsão do tempo' : msg['titulo']!;
    out.add((slot: slot, titulo: titulo, corpo: msg['corpo'] ?? '',
        quandoLocal: quando));
    slot++;
  }
  return out;
}

tz.TZDateTime _tzDe(DateTime local) =>
    tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.UTC, local.millisecondsSinceEpoch);

/// Arma (ou rearma — idempotente, mesmo id sobrescreve) o próximo 05:30.
/// Chamado ao abrir o app com o toggle ligado e ao ligar o toggle.
Future<bool> armarRefreshMadrugada() async {
  // Reserva local desligada (V0.1.224): não arma; cancela o que houver.
  if (!reservaTempoLocalAtiva) {
    try {
      await AndroidAlarmManager.cancel(idRefreshMadrugada);
    } catch (_) {}
    return false;
  }
  try {
    final prox = _tzDe(proximaMadrugada(DateTime.now()));
    return await AndroidAlarmManager.oneShotAt(
      prox,
      idRefreshMadrugada,
      refreshMadrugadaCallback,
      exact: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
    );
  } catch (_) {
    return false;
  }
}

/// Callback de fundo (isolate próprio — top-level + entry-point). Busca o
/// `/tempo_notif`, reescreve os 6:15 e encadeia o próximo 05:30 no `finally`
/// (a cadeia nunca morre por falha de rede/login).
@pragma('vm:entry-point')
Future<void> refreshMadrugadaCallback() async {
  DartPluginRegistrant.ensureInitialized();
  tzdata.initializeTimeZones();
  // Reserva local desligada (V0.1.224): não reagenda nada e encerra a cadeia.
  if (!reservaTempoLocalAtiva) {
    try {
      await AndroidAlarmManager.cancel(idRefreshMadrugada);
    } catch (_) {}
    return;
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(LembretesService.chaveTempoAtivo) ?? false)) {
      try {
        await AndroidAlarmManager.cancel(idRefreshMadrugada);
      } catch (_) {}
      return;
    }
    try {
      await Firebase.initializeApp();
    } catch (_) {}
    final dias = await ChatService.buscarTempoNotif();
    if (dias.isNotEmpty) {
      final plugin = FlutterLocalNotificationsPlugin();
      const androidInit = AndroidInitializationSettings('ic_tempo');
      await plugin.initialize(
        const InitializationSettings(android: androidInit),
        onDidReceiveBackgroundNotificationResponse:
            respostaNotificacaoBackground,
      );
      for (final s in calcularSlotsTempo(dias, DateTime.now())) {
        try {
          await plugin.zonedSchedule(
            LembretesService.idTempoBase + s.slot,
            s.titulo,
            s.corpo,
            _tzDe(s.quandoLocal),
            LembretesService.detalhesTempo(s.titulo, s.corpo),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
        } catch (_) {
          break; // falha preserva os alarmes antigos no lugar
        }
      }
    }
  } catch (_) {
    // best-effort: a cadeia abaixo garante a próxima tentativa
  } finally {
    try {
      await AndroidAlarmManager.oneShotAt(
        _tzDe(proximaMadrugada(DateTime.now())),
        idRefreshMadrugada,
        refreshMadrugadaCallback,
        exact: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
      );
    } catch (_) {}
  }
}
