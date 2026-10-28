import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Dias da semana (1=segunda..7=domingo) p/ o rótulo de recorrência semanal.
const List<String> _diasSem = [
  'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'
];

/// Um lembrete agendado (para exibir/cancelar na lista de pendentes).
class Lembrete {
  Lembrete({
    required this.id,
    required this.texto,
    required this.quando,
    this.recorrencia = 'none',
  });

  final int id;
  final String texto;
  final DateTime quando;
  final String recorrencia; // 'none' | 'diario' | 'semanal'

  bool get repetindo => recorrencia == 'diario' || recorrencia == 'semanal';

  /// Rótulo da repetição p/ exibir ("todo dia 08:00", "toda segunda 09:00").
  String get rotuloRecorrencia {
    final hhmm =
        '${quando.hour.toString().padLeft(2, '0')}:${quando.minute.toString().padLeft(2, '0')}';
    if (recorrencia == 'diario') return 'todo dia $hhmm';
    if (recorrencia == 'semanal') {
      return 'toda ${_diasSem[quando.weekday - 1]} $hhmm';
    }
    return '';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'texto': texto,
        'quando': quando.millisecondsSinceEpoch,
        if (recorrencia != 'none') 'recorrencia': recorrencia,
      };

  factory Lembrete.fromJson(Map<String, dynamic> j) => Lembrete(
        id: j['id'] as int,
        texto: j['texto'] as String,
        quando: DateTime.fromMillisecondsSinceEpoch(j['quando'] as int),
        recorrencia: (j['recorrencia'] as String?) ?? 'none',
      );
}

/// Handler chamado quando o usuário toca na notificação com o app em
/// BACKGROUND / fechado — roda num isolate próprio, por isso precisa ser
/// top-level e anotado com `@pragma('vm:entry-point')`.
@pragma('vm:entry-point')
void respostaNotificacaoBackground(NotificationResponse resposta) async {
  if (resposta.actionId == LembretesService.acaoFeitoId) {
    await LembretesService.concluirPorAcao(resposta);
    return;
  }
  final pedido = LembretesService.pedidoMuseDePayload(resposta.payload);
  // Toque no CORPO de alarme inteligente: guarda p/ o cold start abrir a Muse
  // perguntando (botões de snooze caem no reagendar normal, sem abrir nada).
  if (pedido != null && resposta.actionId == null) {
    await LembretesService.salvarPedidoMuse(pedido.preset, pedido.pergunta);
    return;
  }
  await LembretesService.reagendarPorAcao(resposta);
}

/// Handler com o app VIVO: Feito conclui e atualiza a lista; toque no corpo
/// de alarme inteligente avisa a UI p/ abrir a Muse perguntando; o resto é snooze.
void _respostaNotificacaoForeground(NotificationResponse resposta) async {
  if (resposta.actionId == LembretesService.acaoFeitoId) {
    await LembretesService.concluirPorAcao(resposta);
    await LembretesService.instance.recarregar();
    return;
  }
  final pedido = LembretesService.pedidoMuseDePayload(resposta.payload);
  if (pedido != null && resposta.actionId == null) {
    LembretesService.instance.avisarPedidoMuse(pedido.preset, pedido.pergunta);
    return;
  }
  await LembretesService.reagendarPorAcao(resposta);
  await LembretesService.instance.recarregar();
}

/// Rótulo de um lembrete com o DIA DA SEMANA por extenso, usado no resumo do
/// tempo montado ("monte o tempo (vai somando)"): `22/09 • 09:00 • Terça-feira`.
/// Mostra a data completa (não usa "hoje/amanhã") porque o usuário acabou de
/// somar a duração e quer conferir o dia exato em que vai tocar. O nome
/// completo pode quebrar para a 2ª linha — de propósito, o usuário pediu para
/// NÃO abreviar (V0.1.88).
String quandoComDiaSemana(DateTime dt) {
  const dias = [
    'Segunda-feira',
    'Terça-feira',
    'Quarta-feira',
    'Quinta-feira',
    'Sexta-feira',
    'Sábado',
    'Domingo',
  ];
  final dd = dt.day.toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  final hm = '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
  return '$dd/$mm • $hm • ${dias[dt.weekday - 1]}';
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

  // ===== Lembrete SEMANAL de backup (V0.1.93) =====
  // id FIXO e bem alto (o contador de lembretes rápidos começa em 1 e sobe de
  // 1 em 1 — nunca chega aqui), para agendar/cancelar sem colidir.
  static const int _idBackupSemanal = 900001;
  static const String _chaveBkpAtivo = 'bkp_semanal_ativo_v1';
  static const String _chaveBkpWeekday = 'bkp_semanal_weekday_v1'; // 1=Seg..7=Dom
  static const String _chaveBkpHora = 'bkp_semanal_hora_v1';
  static const String _chaveBkpMin = 'bkp_semanal_min_v1';

  bool _bkpAtivo = false;
  int _bkpWeekday = DateTime.sunday; // domingo por padrão
  int _bkpHora = 19;
  int _bkpMin = 0;

  bool get backupSemanalAtivo => _bkpAtivo;
  int get backupSemanalWeekday => _bkpWeekday;
  int get backupSemanalHora => _bkpHora;
  int get backupSemanalMin => _bkpMin;

  /// Botões de reprogramar que aparecem na notificação (id, rótulo, duração).
  /// O Android mostra até ~3 botões. Nos lembretes o 3º é o "Feito ✓" (concluir
  /// sem abrir é mais comum que adiar 1 dia); o backup semanal mantém os 3
  /// snoozes e não tem Feito, p/ nunca matar a série recorrente sem querer.
  static const List<(String, String, Duration)> _snoozes = [
    ('snooze_30', '30 min', Duration(minutes: 30)),
    ('snooze_120', '2 h', Duration(hours: 2)),
    ('snooze_1440', '24 h', Duration(hours: 24)),
  ];

  /// Ação de concluir o lembrete direto na notificação (sem abrir o app).
  static const String acaoFeitoId = 'feito';

  final List<Lembrete> _pendentes = [];

  /// Lembretes ainda por vir (ordenados por horário; os vencidos somem). Os
  /// RECORRENTES ficam sempre (repetem — a âncora fica no passado, mas seguem ativos).
  List<Lembrete> get pendentes {
    final agora = DateTime.now();
    final vivos = _pendentes
        .where((l) => l.repetindo || l.quando.isAfter(agora))
        .toList()
      ..sort((a, b) => a.quando.compareTo(b.quando));
    return vivos;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Detalhes da notificação. Estático para o handler de background (outro
  /// isolate) montar igual ao do app. [texto] entra no `BigTextStyle` para o
  /// conteúdo escrito aparecer inteiro. Com [conclusao] (lembretes), o 3º botão
  /// é o "Feito ✓" em vez do "+24 h"; sem (backup semanal), os 3 snoozes.
  static NotificationDetails _detalhes(String texto, {bool conclusao = true}) {
    final corpo = texto.isEmpty ? 'Toque para abrir o Taskix' : texto;
    final botoes = conclusao ? _snoozes.take(2).toList() : _snoozes;
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
        styleInformation: BigTextStyleInformation('', contentTitle: corpo, summaryText: 'Taskix'),
        ticker: corpo,
        playSound: true,
        enableVibration: true,
        autoCancel: true,
        showWhen: true,
        ongoing: false,
        actions: [
          if (conclusao)
            const AndroidNotificationAction(
              acaoFeitoId,
              'Feito ✓',
              showsUserInterface: false,
              cancelNotification: true,
            ),
          for (final s in botoes)
            AndroidNotificationAction(
              s.$1,
              s.$2,
              showsUserInterface: false,
              cancelNotification: true,
            ),
        ],
      ),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true, presentBadge: true, threadIdentifier: _canalId),
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
    await _carregarConfigBackup();
    _pronto = true;
    // Reagenda o lembrete semanal (sobrevive a atualização do app / troca de
    // fuso). Silencioso se estiver desligado ou se a permissão faltar.
    if (_bkpAtivo) {
      try {
        await _agendarBackupSemanal();
      } catch (_) {}
    }
  }

  Future<void> _carregarConfigBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _bkpAtivo = prefs.getBool(_chaveBkpAtivo) ?? false;
      _bkpWeekday = prefs.getInt(_chaveBkpWeekday) ?? DateTime.sunday;
      _bkpHora = prefs.getInt(_chaveBkpHora) ?? 19;
      _bkpMin = prefs.getInt(_chaveBkpMin) ?? 0;
    } catch (_) {}
  }

  /// Liga/desliga ou ajusta o horário do lembrete SEMANAL de backup. Com
  /// [ativo] true agenda (pedindo permissão); false cancela. Retorna false se
  /// a permissão de notificação foi negada (o chamador avisa e não liga).
  Future<bool> configurarBackupSemanal({
    required bool ativo,
    int? weekday,
    int? hora,
    int? minuto,
  }) async {
    if (!_pronto) await init();
    if (weekday != null) _bkpWeekday = weekday;
    if (hora != null) _bkpHora = hora;
    if (minuto != null) _bkpMin = minuto;

    if (ativo && !await pedirPermissao()) return false;

    _bkpAtivo = ativo;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chaveBkpAtivo, _bkpAtivo);
    await prefs.setInt(_chaveBkpWeekday, _bkpWeekday);
    await prefs.setInt(_chaveBkpHora, _bkpHora);
    await prefs.setInt(_chaveBkpMin, _bkpMin);

    if (_bkpAtivo) {
      await _agendarBackupSemanal();
    } else {
      await _plugin.cancel(_idBackupSemanal);
    }
    notifyListeners();
    return true;
  }

  /// Próxima ocorrência do weekday/hora escolhidos, a partir de agora.
  tz.TZDateTime _proximaOcorrenciaSemanal() {
    final agora = DateTime.now();
    var alvo = DateTime(agora.year, agora.month, agora.day, _bkpHora, _bkpMin);
    // Avança até cair no dia da semana certo E no futuro.
    while (alvo.weekday != _bkpWeekday || !alvo.isAfter(agora)) {
      alvo = alvo.add(const Duration(days: 1));
    }
    return tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.UTC, alvo.millisecondsSinceEpoch);
  }

  static const String _msgBackup =
      'Backup do Taskix: abra Configurações → Backup e salve suas anotações';

  Future<void> _agendarBackupSemanal() async {
    await _plugin.zonedSchedule(
      _idBackupSemanal,
      _msgBackup,
      '',
      _proximaOcorrenciaSemanal(),
      // Sem "Feito": concluir aqui mataria a série semanal inteira.
      _detalhes(_msgBackup, conclusao: false),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // Repete toda semana no mesmo dia/horário.
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      payload: _msgBackup,
    );
  }

  /// Pede a permissão de notificação (Android 13+). Retorna true se concedida
  /// (ou se não é aplicável). Chamado antes de agendar o primeiro lembrete.
  Future<bool> pedirPermissao() async {
    final a = _android;
    if (a == null) return true;
    final ok = await a.requestNotificationsPermission();
    return ok ?? true;
  }

  /// Agenda um lembrete para daqui a [daqui]. Com [recorrencia] 'diario'/'semanal'
  /// ele REPETE (mesma hora todo dia, ou mesmo dia-da-semana+hora) — a 1ª ocorrência
  /// é [daqui]. Retorna o [Lembrete] criado, ou null se a permissão foi negada.
  /// Com [abrirMusePreset]+[abrirMusePergunta], tocar na notificação abre a Muse
  /// na conversa daquele modo e já envia a pergunta (alarme inteligente).
  Future<Lembrete?> agendar(String texto, Duration daqui,
      {String recorrencia = 'none',
      String? abrirMusePreset,
      String? abrirMusePergunta}) async {
    if (!_pronto) await init();
    if (!await pedirPermissao()) return null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // pega um contador de id atualizado por outro isolate
    final id = prefs.getInt(_chaveProxId) ?? 1;
    await prefs.setInt(_chaveProxId, id + 1);

    final (quando, agendado) = _quandoAgendar(daqui);
    // Repetição via matchDateTimeComponents (mesmo mecanismo do backup semanal).
    final match = recorrencia == 'diario'
        ? DateTimeComponents.time
        : recorrencia == 'semanal'
            ? DateTimeComponents.dayOfWeekAndTime
            : null;

    final pergunta = (abrirMusePergunta ?? '').trim();
    final payload = (abrirMusePreset != null && pergunta.isNotEmpty)
        ? payloadMuse(abrirMusePreset, pergunta)
        : texto;
    final corpo = texto.isEmpty ? 'Toque para abrir o Taskix' : texto;
    await _plugin.zonedSchedule(
      id,
      corpo,
      '',
      agendado,
      _detalhes(texto),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: match,
      payload: payload,
    );

    final l = Lembrete(id: id, texto: texto, quando: quando, recorrencia: recorrencia);
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
  /// Snooze de alarme inteligente mantém o payload `muse:` (continua abrindo
  /// a Muse) e usa o rótulo do lembrete como título.
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

    final payload = resposta.payload ?? '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final id = prefs.getInt(_chaveProxId) ?? 1;
    await prefs.setInt(_chaveProxId, id + 1);

    // Alarme inteligente: título = rótulo do lembrete, payload preservado.
    var titulo = payload;
    final payloadNovo = payload;
    final pedido = pedidoMuseDePayload(payload);
    if (pedido != null) {
      try {
        final raw = prefs.getString(_chavePendentes);
        if (raw != null) {
          final achado = (jsonDecode(raw) as List)
              .map((e) => Lembrete.fromJson(e as Map<String, dynamic>))
              .where((l) => l.id == resposta.id)
              .toList();
          if (achado.isNotEmpty) titulo = achado.first.texto;
        }
      } catch (_) {}
    }

    final (quando, agendado) = _quandoAgendar(dur);

    final corpo2 = titulo.isEmpty ? 'Toque para abrir o Taskix' : titulo;
    await plugin.zonedSchedule(
      id,
      corpo2,
      '',
      agendado,
      _detalhes(titulo),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payloadNovo,
    );

    // Atualiza a lista persistida: tira o lembrete que disparou, põe o novo.
    await _mexerPendentesPrefs(
      prefs,
      removerId: resposta.id,
      adicionar: Lembrete(id: id, texto: titulo, quando: quando),
    );
  }

  static Duration? _duracaoDaAcao(String? actionId) {
    if (actionId == null) return null;
    for (final s in _snoozes) {
      if (s.$1 == actionId) return s.$3;
    }
    return null;
  }

  // ===== Alarme inteligente: tocar abre a Muse e pergunta sozinho =====
  // Payload `muse:<preset>:<pergunta>` (preset = coach|projetos|geral).
  static const String prefixoMuse = 'muse:';

  /// Monta o payload de um alarme inteligente.
  static String payloadMuse(String preset, String pergunta) =>
      '$prefixoMuse${preset.trim()}:${pergunta.trim()}';

  /// Presets válidos p/ abrir direto (o mesmo trio do menu de modo da Muse).
  static const Set<String> presetsMuseValidos = {'coach', 'projetos', 'geral'};

  /// Extrai (preset, pergunta) do payload; null se não for alarme inteligente.
  static ({String preset, String pergunta})? pedidoMuseDePayload(String? payload) {
    if (payload == null || !payload.startsWith(prefixoMuse)) return null;
    final resto = payload.substring(prefixoMuse.length);
    final i = resto.indexOf(':');
    if (i < 0) return null;
    final preset = resto.substring(0, i).trim();
    final pergunta = resto.substring(i + 1).trim();
    if (!presetsMuseValidos.contains(preset) || pergunta.isEmpty) return null;
    return (preset: preset, pergunta: pergunta);
  }

  /// Pedido pendente p/ a Muse (alarme tocado): o app consome ao abrir/retomar.
  /// Em disco p/ funcionar com o app fechado (isolate de background só escreve
  /// prefs); em memória + notify p/ quando o app já está vivo.
  static const String chavePedidoMuse = 'muse_pedido_v1';
  ({String preset, String pergunta})? _pedidoMuse;
  ({String preset, String pergunta})? get pedidoMusePendente => _pedidoMuse;

  /// Avisa a UI de um pedido da Muse (alarme inteligente tocado com o app
  /// vivo): a tela abre o chat e pergunta sozinho. Consumo único via
  /// [pedidoMusePendente] (quem consome zera).
  void avisarPedidoMuse(String preset, String pergunta) {
    _pedidoMuse = (preset: preset, pergunta: pergunta);
    notifyListeners();
  }

  /// Limpa o pedido pendente sem executar (ex.: Muse já aberta).
  void descartarPedidoMuse() {
    _pedidoMuse = null;
  }

  static Future<void> salvarPedidoMuse(String preset, String pergunta) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(chavePedidoMuse, payloadMuse(preset, pergunta));
    } catch (_) {}
  }

  /// Lê e apaga o pedido (consumo único — tocar 2x não pergunta 2x).
  static Future<({String preset, String pergunta})?> lerEConsumirPedidoMuse() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString(chavePedidoMuse);
      if (raw == null) return null;
      await prefs.remove(chavePedidoMuse);
      return pedidoMuseDePayload(raw);
    } catch (_) {
      return null;
    }
  }

  /// Conclui o lembrete direto na notificação (botão "Feito ✓"): cancela o
  /// alarme e tira dos pendentes, sem abrir o app. Série recorrente (backup
  /// semanal ou lembrete diario/semanal) NÃO é cancelada — só descarta o aviso.
  static Future<void> concluirPorAcao(NotificationResponse resposta) async {
    try {
      if (resposta.id == null || resposta.id == _idBackupSemanal) return;
      final plugin = FlutterLocalNotificationsPlugin();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      // Recorrente: não mexe na série (o próximo disparo continua valendo).
      var ehRecorrente = false;
      try {
        final raw = prefs.getString(_chavePendentes);
        if (raw != null) {
          ehRecorrente = (jsonDecode(raw) as List)
              .map((e) => Lembrete.fromJson(e as Map<String, dynamic>))
              .any((l) => l.id == resposta.id && l.repetindo);
        }
      } catch (_) {}
      if (!ehRecorrente) {
        try {
          await plugin.cancel(resposta.id!);
        } catch (_) {}
        await _mexerPendentesPrefs(prefs, removerId: resposta.id);
      }
    } catch (_) {}
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
