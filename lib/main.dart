import 'package:flutter/material.dart';

import 'projetos_screen.dart';

void main() {
  runApp(const AdmProjetosApp());
}

class AdmProjetosApp extends StatelessWidget {
  const AdmProjetosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ADM-projetos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const ProjetosScreen(),
    );
  }
}