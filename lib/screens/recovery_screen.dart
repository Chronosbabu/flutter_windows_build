import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../frais_scolaires.dart';
import '../app_state.dart';
import 'school_home_screen.dart';

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  bool isRecoverMode = true;
  final codeController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;
  String? errorMessage;

  Future<void> _handleAction() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final fraisScolaires = FraisScolaires();

    String code = codeController.text.trim();
    String password = passwordController.text.trim();

    if (code.isEmpty || password.isEmpty) {
      setState(() => errorMessage = "Veuillez remplir les deux champs");
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    print("🔄 Début de ${isRecoverMode ? 'RÉCUPÉRATION' : 'CRÉATION'}");
    print("Code: $code | Mot de passe: ${password.isNotEmpty ? '***' : 'vide'}");

    if (isRecoverMode) {
      bool success = await fraisScolaires.restoreFromServer(code, password);

      if (success) {
        await appState.setSchoolCode(code);
        await appState.setBackupPassword(password);
        print("✅ Récupération réussie !");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Données récupérées avec succès !"), backgroundColor: Colors.green),
          );
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SchoolHomeScreen()));
        }
      } else {
        setState(() => errorMessage = "Échec de récupération.\nVérifiez le code et le mot de passe.\n\nEssayez de refaire une sauvegarde depuis le téléphone.");
        print("❌ Échec de restoreFromServer");
      }
    } else {
      // Nouvelle école
      await appState.setSchoolCode(code);
      await appState.setBackupPassword(password);
      await fraisScolaires.loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Nouvelle école créée"), backgroundColor: Colors.green),
        );
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SchoolHomeScreen()));
      }
    }

    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Colors.indigo, Colors.teal], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.school, size: 90, color: Colors.white),
                  const SizedBox(height: 20),
                  Text(
                    isRecoverMode ? "Récupérer mes Données" : "Nouvelle École",
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 40),

                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text("Récupérer")),
                      ButtonSegment(value: false, label: Text("Nouvelle École")),
                    ],
                    selected: {isRecoverMode},
                    onSelectionChanged: (set) {
                      setState(() => isRecoverMode = set.first);
                      errorMessage = null;
                    },
                  ),

                  const SizedBox(height: 30),

                  TextField(
                    controller: codeController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Code de l'École",
                      hintText: "Ex: MAPENDO2026",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Mot de Passe de Sauvegarde",
                      border: OutlineInputBorder(),
                    ),
                  ),

                  if (errorMessage != null) ...[
                    const SizedBox(height: 20),
                    Text(errorMessage!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
                  ],

                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _handleAction,
                      child: isLoading
                          ? const CircularProgressIndicator()
                          : Text(isRecoverMode ? "RÉCUPÉRER MES DONNÉES" : "CRÉER LA NOUVELLE ÉCOLE"),
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
