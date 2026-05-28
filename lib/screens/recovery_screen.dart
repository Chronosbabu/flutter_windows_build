
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
  bool isRecoverMode = true; // true = Récupérer | false = Nouvelle école

  final codeController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;
  String? errorMessage;

  Future<void> _handleAction() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final fraisScolaires = FraisScolaires();

    if (codeController.text.trim().isEmpty || passwordController.text.trim().isEmpty) {
      setState(() => errorMessage = "Veuillez remplir les deux champs");
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    String code = codeController.text.trim();
    String password = passwordController.text.trim();

    if (isRecoverMode) {
      // === MODE RÉCUPÉRATION ===
      await fraisScolaires.loadData();
      bool success = await fraisScolaires.restoreFromServer(code, password);

      if (success) {
        await appState.setSchoolCode(code);
        await appState.setBackupPassword(password);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Données récupérées avec succès !"), backgroundColor: Colors.green));
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SchoolHomeScreen()));
        }
      } else {
        setState(() => errorMessage = "Échec de récupération.\nVérifiez votre code et mot de passe.");
      }
    } else {
      // === MODE NOUVELLE ÉCOLE ===
      await appState.setSchoolCode(code);
      await appState.setBackupPassword(password);

      // Créer une nouvelle configuration
      await fraisScolaires.loadData(); // Charge les données par défaut

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Nouvelle école créée avec succès !"), backgroundColor: Colors.green));
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
                  const SizedBox(height: 10),

                  Text(
                    isRecoverMode
                        ? "Entrez vos identifiants pour restaurer toutes vos données"
                        : "Créez votre nouvelle école",
                    style: const TextStyle(fontSize: 16, color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // Toggle entre les deux modes
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
                      labelStyle: TextStyle(color: Colors.white70),
                      hintText: "Ex: MAPENDO2026",
                      border: OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Mot de Passe de Sauvegarde",
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                    ),
                  ),

                  if (errorMessage != null) ...[
                    const SizedBox(height: 20),
                    Text(errorMessage!, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  ],

                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _handleAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.indigo,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isLoading
                          ? const CircularProgressIndicator(color: Colors.indigo)
                          : Text(
                        isRecoverMode ? "RÉCUPÉRER MES DONNÉES" : "CRÉER LA NOUVELLE ÉCOLE",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
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