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
    final seed = const Color(0xFF2563EB);
    return ListenableBuilder(
      listenable: temaController,
      builder: (context, _) {
        return MaterialApp(
          title: 'ADM-projetos',
          debugShowCheckedModeBanner: false,
          themeMode: temaController.modo,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: seed),
            useMaterial3: true,
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
            ),
          ),
          home: const ProjetosScreen(),
        );
      },
    );
  }
}