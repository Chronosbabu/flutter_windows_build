import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_state.dart';
import 'frais_scolaires.dart';
import 'screens/school_home_screen.dart';
import 'screens/recovery_screen.dart';   // ← Nouveau écran

const String serverUrl = "https://jsinf.onrender.com";

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestion des Frais Scolaires',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: Provider.of<AppState>(context).isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const InitialScreen(),   // ← Changement ici
      debugShowCheckedModeBanner: false,
    );
  }
}

// ==================== NOUVEL ÉCRAN INITIAL ====================
class InitialScreen extends StatelessWidget {
  const InitialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    // Si l'utilisateur a déjà un code → aller directement à l'accueil
    if (appState.schoolCode != null && appState.backupPassword != null) {
      return const MainHomeScreen();
    }

    // Sinon → écran de récupération / première configuration
    return const RecoveryScreen();
  }
}

class MainHomeScreen extends StatelessWidget {
  const MainHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    return Scaffold(
      appBar: AppBar(title: Text(appState.schoolName), centerTitle: true),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Colors.indigo, Colors.teal], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(appState.schoolName, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 80),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.school, size: 32),
                    label: const Text("Commencer la Gestion", style: TextStyle(fontSize: 20)),
                    onPressed: () {
                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SchoolHomeScreen()));
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
