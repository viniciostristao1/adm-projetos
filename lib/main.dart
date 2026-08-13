import 'package:flutter/material.dart';

import 'cores.dart';
import 'projetos_screen.dart';
import 'tema.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  temaController.carregar();
  runApp(const AdmProjetosApp());
}

class AdmProjetosApp extends StatelessWidget {
  static const _bordaCard = Color(0x1A0B1220);

  static const _appbarClaro = AppBarTheme(
    backgroundColor: Color(0xFFFFFFFF),
    foregroundColor: Color(0xFF1E3A8A),
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
      color: Color(0xFF1E3A8A),
    ),
  );

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

  ThemeData _temaClaro() => _temaBase(ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A8A)),
      extensions: const [AppCores.luz],
      appBarTheme: _appbarClaro,
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppCores.luz.fab,
        foregroundColor: AppCores.luz.fabIcone,
      ),
    ));

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

  ThemeData _temaBegeNeum() => _temaNeum(AppCores.begeNeum);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: temaController,
      builder: (context, _) {
        final modo = temaController.modo;
        final escuro =
            modo == Modo.escuro || modo == Modo.neumB;
        final scale = temaController.fonte.scale;
        final theme = switch (modo) {
          Modo.claro => _temaClaro(),
          Modo.bege => _temaNeum(AppCores.bege),
          Modo.escuro => _temaClaro(), // não usado (themeMode.dark)
          Modo.neumB => _temaNeumB(),
          Modo.begeNeum => _temaBegeNeum(),
        };
        final darkTheme = switch (modo) {
          Modo.escuro => _temaEscuro(),
          Modo.neumB => _temaNeumB(),
          _ => _temaEscuro(),
        };
        return MaterialApp(
          title: 'ADM-projetos',
          debugShowCheckedModeBanner: false,
          themeMode: escuro ? ThemeMode.dark : ThemeMode.light,
          theme: theme,
          darkTheme: darkTheme,
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