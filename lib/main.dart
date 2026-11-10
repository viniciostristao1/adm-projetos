import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'barra_config.dart';
import 'chat/chat_config.dart';
import 'chat/chat_store.dart';
import 'cores.dart';
import 'diagnostico.dart';
import 'home_shell.dart';
import 'lembretes.dart';
import 'push_tempo.dart';
import 'storage.dart';
import 'sync_service.dart';
import 'tema.dart';
import 'voz_config.dart';

Future<void> main() async {
  // Tudo dentro de uma zona guardada p/ capturar erros não-tratados (async
  // inclusive) num relatório que o usuário pode enviar/compartilhar (Diagnostico).
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    Diagnostico.carregar();
    // Erros do framework (build/layout/gesture) e da plataforma vão ao relatório.
    final anterior = FlutterError.onError;
    FlutterError.onError = (details) {
      anterior?.call(details);
      Diagnostico.registrar(
          'flutter', details.exceptionAsString(), details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      Diagnostico.registrar('plataforma', error, stack);
      return true; // tratado (não derruba o app)
    };
    temaController.carregar();
    barraController.carregar();
    vozController.carregar();
    // Salva na hora quando o app sai de primeiro plano (fechar/minimizar) —
    // garante que o texto recém-digitado não se perca.
    WidgetsBinding.instance.addObserver(_SalvadorDeVida());
    // Pré-aquece o histórico do Muse CEDO (antes da 1ª tela) p/ a 1ª abertura do
    // chat não piscar na tela de loading. Fire-and-forget; só com o chat ligado.
    if (ChatConfig.habilitado) ChatStore.aquecer();
    // Firebase: se ainda não estiver configurado (sem google-services.json),
    // o app continua funcionando 100% local.
    try {
      await Firebase.initializeApp();
      await SyncService.instance.iniciar();
    } catch (e) {
      debugPrint('Firebase indisponível (modo local): $e');
    }
    // Lembretes (notificação local) — se falhar, o app segue sem o recurso.
    try {
      await LembretesService.instance.init();
      // Motor do refresh de madrugada da previsão (alarme exato 05:30 que
      // reescreve os 6:15 com dado fresco; auto-perpétuo a partir daqui).
      try {
        await AndroidAlarmManager.initialize();
      } catch (e) {
        debugPrint('AlarmManager indisponível: $e');
      }
    } catch (e) {
      debugPrint('Lembretes indisponíveis: $e');
    }
    // Push da previsão do tempo (6:15) vindo do servidor (FCM) — à prova de
    // Doze/OEM. Primeiro consome (AWAIT) um toque que abriu o app a partir de
    // MORTO, p/ a ProjetosScreen achar o pedido da Muse no disco já no initState.
    await PushTempo.consumirToqueInicial();
    // Resto (canal, token, listeners) fire-and-forget: faz rede, não trava o
    // boot. Best-effort (nunca lança).
    PushTempo.init();
    runApp(const AdmProjetosApp());
  }, (error, stack) {
    Diagnostico.registrar('zona', error, stack);
  });
}

/// Salva os dados em qualquer mudança de ciclo de vida que tire o app da
/// tela (pausa, inativo, oculto) — reforço além do debounce das caixinhas.
class _SalvadorDeVida with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      Storage.instance.salvar();
    }
  }
}

class AdmProjetosApp extends StatelessWidget {
  static const _bordaCard = Color(0x1AFFFFFF);

  const AdmProjetosApp({super.key});

  ThemeData _temaBase(ThemeData t) => t.copyWith(
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF0B1220).withValues(alpha: 0.03),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: _bordaCard),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titleTextStyle: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  /// Tema Azul (estilo Calis Timer): navy escuro plano com accent azul,
  /// cartões arredondados (18) com borda sutil, inputs preenchidos.
  ThemeData _temaAzul() {
    const bg = Color(0xFF0A0F1C);
    const surface = Color(0xFF121A2E);
    const surface2 = Color(0xFF1B2540);
    const text = Color(0xFFEAF0FB);
    const accent = Color(0xFF3B82F6);
    const onAccent = Color(0xFFF2F7FF);
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: surface,
        onSurface: text,
      ).copyWith(primary: accent, onPrimary: onAccent),
      scaffoldBackgroundColor: bg,
      extensions: const [AppCores.azul],
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: text,
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: Color(0xFF8A96AE),
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: Color(0x14FFFFFF)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: onAccent,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        hintStyle: TextStyle(color: Color(0xFF56607A)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: surface,
        selectedColor: Color(0xFF1E4A9E),
        labelStyle: TextStyle(color: text, fontWeight: FontWeight.w700),
        side: BorderSide(color: Color(0x14FFFFFF)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// Tema claro plano (estilo Calis Timer — madeira): Bege usa esta
  /// estrutura; a barra superior pode ter cor própria ([appBarColor],
  /// padrão: mesma do fundo).
  ThemeData _temaClaroCalis({
    required Color bg,
    required Color surface,
    required Color surface2,
    required Color text,
    required Color accent,
    required Color onAccent,
    required AppCores app,
    Color? appBarColor,
  }) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
        surface: surface,
        onSurface: text,
      ).copyWith(primary: accent, onPrimary: onAccent),
      scaffoldBackgroundColor: bg,
      extensions: [app],
      appBarTheme: AppBarTheme(
        backgroundColor: appBarColor ?? bg,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: text,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: text.withValues(alpha: 0.55),
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          side: BorderSide(color: text.withValues(alpha: 0.1)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: onAccent,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        hintStyle: TextStyle(color: text.withValues(alpha: 0.45)),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: accent.withValues(alpha: 0.25),
        labelStyle: TextStyle(color: text, fontWeight: FontWeight.w700),
        side: BorderSide(color: text.withValues(alpha: 0.1)),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// Calis, mas: intervenções/botões em PRETO, detalhe próprio (terracota no
  /// Creme, verde no Papel) e títulos serifados. O builder recebe o detalhe
  /// como acento (abas/chips) e o preto sobrescreve FAB/primária.
  ThemeData _temaCremePapel({
    required Color bg,
    required Color surface,
    required Color surface2,
    required Color text,
    required Color detalhe,
    required AppCores app,
    required Color appBarColor,
  }) {
    const preto = AppCores.kPretoCremePapel;
    const onPreto = Colors.white;
    final t = _temaClaroCalis(
      bg: bg,
      surface: surface,
      surface2: surface2,
      text: text,
      accent: detalhe,
      onAccent: Colors.white,
      app: app,
      appBarColor: appBarColor,
    );
    TextStyle serif(TextStyle? s) =>
        (s ?? const TextStyle()).copyWith(fontFamily: 'SourceSerif');
    final tx = t.textTheme;
    return t.copyWith(
      colorScheme: t.colorScheme.copyWith(
        primary: preto,
        onPrimary: onPreto,
        secondary: detalhe,
        tertiary: detalhe,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: preto,
        foregroundColor: onPreto,
        // Sem sombra: o FAB preto flutua sobre a ponta direita da barra
        // (região do Estudos, com extendBody) e a sombra caía ali como um
        // borrão escuro no fundo claro. Botão chapado combina com o plano.
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      tabBarTheme: t.tabBarTheme.copyWith(labelColor: preto),
      textTheme: tx.copyWith(
        displayLarge: serif(tx.displayLarge),
        displayMedium: serif(tx.displayMedium),
        displaySmall: serif(tx.displaySmall),
        headlineLarge: serif(tx.headlineLarge),
        headlineMedium: serif(tx.headlineMedium),
        headlineSmall: serif(tx.headlineSmall),
        titleLarge: serif(tx.titleLarge),
      ),
      appBarTheme: t.appBarTheme.copyWith(
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: text,
          fontFamily: 'SourceSerif',
        ),
      ),
      dialogTheme: t.dialogTheme.copyWith(
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: text,
          fontFamily: 'SourceSerif',
        ),
      ),
    );
  }

  /// Tema Creme — fundo bege, botões pretos, detalhe terracota.
  ThemeData _temaCreme() => _temaCremePapel(
        bg: const Color(0xFFF5F0E6),
        surface: const Color(0xFFFFFFFF),
        surface2: const Color(0xFFEFE7D8),
        text: const Color(0xFF1F1B16),
        detalhe: const Color(0xFFC96F4A),
        app: AppCores.creme,
        appBarColor: const Color(0xFFF5F0E6),
      );

  /// Tema Papel — fundo off-white, botões pretos, detalhe verde.
  ThemeData _temaPapel() => _temaCremePapel(
        bg: const Color(0xFFFAF8F5),
        surface: const Color(0xFFFFFFFF),
        surface2: const Color(0xFFF0EBE4),
        text: const Color(0xFF1A1A1A),
        detalhe: const Color(0xFF1E9E6A),
        app: AppCores.papel,
        appBarColor: const Color(0xFFFAF8F5),
      );

  /// Tema neumórfico (Dark Game e Bege Game; o bege clássico também usa, com
  /// cartões/barra marrons). Luz ↗ superior esquerda, sombras duplas difusas,
  /// inner shadow nos pressionados, sem contornos.
  ThemeData _temaNeum(AppCores app) {
    final claro =
        ThemeData.estimateBrightnessForColor(app.fundoFim) == Brightness.light;
    return ThemeData(
      fontFamily: 'Manrope',
      colorScheme: ColorScheme.fromSeed(
        seedColor: app.fab,
        brightness: claro ? Brightness.light : Brightness.dark,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      extensions: [app],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: app.textoUI,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color: app.textoUI,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: app.textoUI,
        unselectedLabelColor: app.textoUI.withValues(alpha: 0.55),
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        indicator: BoxDecoration(
          color: app.fab.withValues(alpha: claro ? 0.2 : 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: app.fab,
        foregroundColor: app.fabIcone,
        elevation: 8,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: app.notaFim,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: app.notaInicio,
        selectedColor: app.fab.withValues(alpha: 0.22),
        labelStyle: TextStyle(
          color: app.textoUI,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        secondaryLabelStyle: TextStyle(
          color: app.textoUI.withValues(alpha: 0.65),
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  ThemeData _temaNeumB() => _temaNeum(AppCores.neumB);
  /// Tema Dark (V0.1.199) — espelha o app do Claude em modo escuro: fundo
  /// preto QUENTE, superfícies #262524 com borda sutil, texto branco quente,
  /// acento terracota e títulos serifados. Plano, sem sombras.
  ThemeData _temaDark() {
    const bg = Color(0xFF1E1D1C);
    const surface = Color(0xFF262524);
    const borda = Color(0xFF3A3836);
    const text = Color(0xFFF5F1EA);
    const text2 = Color(0xFFA8A29A);
    const accent = Color(0xFFD97757);
    const onAccent = Color(0xFF1E1D1C);
    TextStyle serif(TextStyle? s) =>
        (s ?? const TextStyle()).copyWith(fontFamily: 'SourceSerif');
    final t = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: surface,
        onSurface: text,
      ).copyWith(primary: accent, onPrimary: onAccent),
      scaffoldBackgroundColor: bg,
      extensions: const [AppCores.dark],
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: text,
          fontFamily: 'SourceSerif',
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: text,
        unselectedLabelColor: text2,
        dividerColor: Colors.transparent,
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.tab,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borda),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: onAccent,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: text.withValues(alpha: 0.45)),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
          borderSide: BorderSide(color: borda),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
          borderSide: BorderSide(color: borda),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
          borderSide: BorderSide(color: text2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: accent.withValues(alpha: 0.25),
        labelStyle:
            const TextStyle(color: text, fontWeight: FontWeight.w700),
        side: const BorderSide(color: borda),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        backgroundColor: surface,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: text,
          fontFamily: 'SourceSerif',
        ),
      ),
    );
    final tx = t.textTheme;
    return t.copyWith(
      textTheme: tx.copyWith(
        displayLarge: serif(tx.displayLarge),
        displayMedium: serif(tx.displayMedium),
        displaySmall: serif(tx.displaySmall),
        headlineLarge: serif(tx.headlineLarge),
        headlineMedium: serif(tx.headlineMedium),
        headlineSmall: serif(tx.headlineSmall),
        titleLarge: serif(tx.titleLarge),
      ),
    );
  }

  /// Tema Ônix (estilo ChatGPT): preto liso, texto branco e um verde discreto
  /// só no accent. Home sem caixas (ver projetos_screen). Fonte sem serifa
  /// padrão do sistema (a do ChatGPT é fechada).
  ThemeData _temaOnix() {
    const bg = Color(0xFF0D0D0D);
    const surface = Color(0xFF1E1F20);
    const borda = Color(0xFF2A2A2B);
    const text = Color(0xFFECECEC);
    const text2 = Color(0xFF9A9A9A);
    const accent = Color(0xFF19C37D);
    const onAccent = Color(0xFF052B1B);
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: surface,
        onSurface: text,
      ).copyWith(primary: accent, onPrimary: onAccent),
      scaffoldBackgroundColor: bg,
      extensions: const [AppCores.onix],
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: text,
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: text,
        unselectedLabelColor: text2,
        dividerColor: Colors.transparent,
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.tab,
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: onAccent,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: Color(0xFF6E6E6E)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: borda),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: surface,
        selectedColor: Color(0x2A19C37D),
        labelStyle: TextStyle(color: text, fontWeight: FontWeight.w500),
        side: BorderSide(color: borda),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          side: BorderSide(color: borda),
        ),
        backgroundColor: surface,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: temaController,
      builder: (context, _) {
        final modo = temaController.modo;
        final scale = temaController.fonte.scale;
        // Creme e Papel são os claros; demais escuros.
        final claro = modo == Modo.creme || modo == Modo.papel;
        final theme = switch (modo) {
          Modo.azul => _temaAzul(),
          Modo.neumB => _temaNeumB(),
          Modo.onix => _temaOnix(),
          Modo.creme => _temaCreme(),
          Modo.papel => _temaPapel(),
          Modo.dark => _temaDark(),
        };
        return MaterialApp(
          title: 'Taskix',
          debugShowCheckedModeBanner: false,
          themeMode: claro ? ThemeMode.light : ThemeMode.dark,
          theme: theme,
          darkTheme: theme,
          builder: (context, child) {
            final data = MediaQuery.of(context);
            return MediaQuery(
              data: data.copyWith(
                textScaler: TextScaler.linear(
                    scale * data.textScaler.scale(1)),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  iconTheme: Theme.of(context)
                      .iconTheme
                      .copyWith(size: 24 * scale),
                ),
                child: child!,
              ),
            );
          },
          home: const HomeShell(),
        );
      },
    );
  }
}