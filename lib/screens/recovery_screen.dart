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

  // Code secret pour créer une nouvelle école sans internet
  final String secretNewSchoolCode = "babu12@@12##chronos";

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

    print("🔄 Tentative de ${isRecoverMode ? 'RÉCUPÉRATION' : 'CRÉATION NOUVELLE ÉCOLE'}");
    print("Code entré: $code");

    if (isRecoverMode) {
      // === MODE RÉCUPÉRATION (nécessite internet) ===
      print("🌐 Mode Récupération - Contact du serveur...");
      bool success = await fraisScolaires.restoreFromServer(code, password);

      print("📡 Résultat restoreFromServer : $success");

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
        setState(() => errorMessage = "Échec de récupération.\nVérifiez le code et le mot de passe.\n\nAssurez-vous d'avoir fait une sauvegarde avant.");
        print("❌ Échec de restoreFromServer");
      }
    } else {
      // === MODE NOUVELLE ÉCOLE ===
      if (code != secretNewSchoolCode) {
        setState(() => errorMessage = "Code secret incorrect.\nLe code administrateur est requis pour créer une nouvelle école.");
        print("❌ Code secret incorrect pour nouvelle école");
      } else {
        await appState.setSchoolCode(code);
        await appState.setBackupPassword(password);
        await fraisScolaires.loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Nouvelle école créée avec succès"), backgroundColor: Colors.green),
          );
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SchoolHomeScreen()));
        }
      }
    }

    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.indigo, Colors.teal],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
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

                  // Champ Code (masqué en mode Nouvelle École)
                  TextField(
                    controller: codeController,
                    obscureText: !isRecoverMode,   // Masqué seulement en mode Nouvelle École
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: isRecoverMode ? "Code de l'École" : "Code Secret Administrateur",
                      hintText: isRecoverMode ? "Ex: MAPENDO2026" : "••••••••••••••••",
                      border: const OutlineInputBorder(),
                      labelStyle: const TextStyle(color: Colors.white),
                      hintStyle: const TextStyle(color: Colors.white70),
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
                      labelStyle: TextStyle(color: Colors.white),
                    ),
                  ),

                  if (errorMessage != null) ...[
                    const SizedBox(height: 20),
                    Text(errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 15), textAlign: TextAlign.center),
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
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
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
