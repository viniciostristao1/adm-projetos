import 'package:flutter/material.dart';

import 'projetos_screen.dart';
import 'tema.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  temaController.carregar();
  runApp(const AdmProjetosApp());
}

class AdmProjetosApp extends StatelessWidget {
  const AdmProjetosApp({super.key});

  @override
  Widget build(BuildContext context) {
    final seed = const Color(0xFF1E3A8A);
    return ListenableBuilder(
      listenable: temaController,
      builder: (context, _) {
        return MaterialApp(
          title: 'ADM-projetos',
          debugShowCheckedModeBanner: false,
          themeMode: temaController.modo,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: const Color(0xFF0B1220).withValues(alpha: 0.03),
            ),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              titleTextStyle: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: const Color(0xFF0B1220).withValues(alpha: 0.08),
                ),
              ),
              color: ThemeData.light().colorScheme.surface,
            ),
            listTileTheme: const ListTileThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
              ),
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
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
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
            ),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              titleTextStyle: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              color: ThemeData.dark().colorScheme.surface,
            ),
            listTileTheme: const ListTileThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
              ),
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
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
          ),
          home: const ProjetosScreen(),
        );
      },
    );
  }
}