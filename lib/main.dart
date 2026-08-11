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

  static const _appbarBege = AppBarTheme(
    backgroundColor: Color(0xFF6D4C2F),
    foregroundColor: Color(0xFFFBF3E8),
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
      color: Color(0xFFFBF3E8),
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

  ThemeData _temaBege() => _temaBase(ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6D4C2F)),
        scaffoldBackgroundColor: const Color(0xFFEDE1CF),
        extensions: const [AppCores.bege],
        appBarTheme: _appbarBege,
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: AppCores.bege.fab,
          foregroundColor: AppCores.bege.fabIcone,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: const Color(0xFF6D4C2F).withValues(alpha: 0.15),
            ),
          ),
        ),
      ));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: temaController,
      builder: (context, _) {
        final modo = temaController.modo;
        final usarBege = modo == Modo.bege;
        final scale = temaController.fonte.scale;
        return MaterialApp(
          title: 'ADM-projetos',
          debugShowCheckedModeBanner: false,
          themeMode: temaController.themeFlutter,
          theme: usarBege ? _temaBege() : _temaClaro(),
          darkTheme: _temaEscuro(),
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