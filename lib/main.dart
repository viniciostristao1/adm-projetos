import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'barra_config.dart';
import 'cores.dart';
import 'lembretes.dart';
import 'projetos_screen.dart';
import 'storage.dart';
import 'sync_service.dart';
import 'tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  temaController.carregar();
  barraController.carregar();
  // Salva na hora quando o app sai de primeiro plano (fechar/minimizar) —
  // garante que o texto recém-digitado não se perca.
  WidgetsBinding.instance.addObserver(_SalvadorDeVida());
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
  } catch (e) {
    debugPrint('Lembretes indisponíveis: $e');
  }
  runApp(const AdmProjetosApp());
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

  static const _appbarEscuro = AppBarTheme(
    backgroundColor: Colors.black,
    foregroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
      color: Colors.white,
    ),
  );

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

  ThemeData _temaBege() => _temaClaroCalis(
        // Fundo da página principal: bege CLARO.
        bg: const Color(0xFFF2E8D6),
        surface: const Color(0xFFE0D1B9),
        surface2: const Color(0xFFCBB897),
        text: const Color(0xFF382E20),
        accent: const Color(0xFFB5652E),
        onAccent: const Color(0xFFFFF3E7),
        app: AppCores.bege,
        // Barra superior (página principal e projeto) na cor bege escuro —
        // a mesma do interior das caixinhas.
        appBarColor: const Color(0xFFE0D1B9),
      );

  ThemeData _temaEscuro() => _temaBase(ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
        extensions: const [AppCores.escuro],
        appBarTheme: _appbarEscuro,
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: AppCores.escuro.fab,
          foregroundColor: AppCores.escuro.fabIcone,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
        ),
      ));

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

  /// Tema Claude Code: terminal escuro. Preto-quente sólido, superfícies com
  /// borda de 1px (sem sombras), acento terracota e fonte monoespaçada.
  ThemeData _temaClaude() {
    const bg = Color(0xFF0C0C0D);
    const surface = Color(0xFF161617);
    const borda = Color(0xFF2A2A2B);
    const text = Color(0xFFF0EEE9);
    const text2 = Color(0xFF8A8A8A);
    const accent = Color(0xFFD97757);
    const onAccent = Color(0xFF120806);
    return ThemeData(
      fontFamily: 'JetBrainsMono',
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: surface,
        onSurface: text,
      ).copyWith(primary: accent, onPrimary: onAccent),
      scaffoldBackgroundColor: bg,
      extensions: const [AppCores.claude],
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
        labelColor: accent,
        unselectedLabelColor: text2,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          side: BorderSide(color: borda),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: onAccent,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: Color(0xFF6E6E6E)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: borda),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: surface,
        selectedColor: Color(0x2AD97757),
        labelStyle: TextStyle(color: text, fontWeight: FontWeight.w500),
        side: BorderSide(color: borda),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
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
        // Bege é o único claro (madeira do Calis Timer); demais escuros.
        final claro = modo == Modo.bege;
        final theme = switch (modo) {
          Modo.azul => _temaAzul(),
          Modo.escuro => _temaEscuro(),
          Modo.neumB => _temaNeumB(),
          Modo.bege => _temaBege(),
          Modo.claude => _temaClaude(),
          Modo.onix => _temaOnix(),
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
          home: const ProjetosScreen(),
        );
      },
    );
  }
}