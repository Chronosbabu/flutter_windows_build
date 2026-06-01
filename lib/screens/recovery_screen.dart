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
  bool isRecoverMode = true; // true = J'ai déjà un compte | false = Nouvelle école

  final idController = TextEditingController();        // ID École fourni par admin
  final passwordController = TextEditingController();
  bool isLoading = false;
  String? errorMessage;

  Future<void> _handleAction() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final fraisScolaires = FraisScolaires();

    String schoolId = idController.text.trim();
    String password = passwordController.text.trim();

    if (schoolId.isEmpty || password.isEmpty) {
      setState(() => errorMessage = "Veuillez remplir les deux champs");
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    print("🔄 Tentative - ID: $schoolId | Mode: ${isRecoverMode ? 'Récupération' : 'Nouvelle école'}");

    if (isRecoverMode) {
      // RÉCUPÉRATION (déjà inscrit)
      bool success = await fraisScolaires.restoreFromServer(schoolId, password);

      if (success) {
        await appState.setSchoolCode(schoolId);
        await appState.setBackupPassword(password);
        print("✅ Récupération réussie");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Connexion réussie !"), backgroundColor: Colors.green),
          );
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SchoolHomeScreen()));
        }
      } else {
        setState(() => errorMessage = "ID ou mot de passe incorrect.\nVérifiez vos informations.");
      }
    } else {
      // NOUVELLE ÉCOLE (première inscription)
      await appState.setSchoolCode(schoolId);
      await appState.setBackupPassword(password);
      await fraisScolaires.loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ École enregistrée avec succès !"), backgroundColor: Colors.green),
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
                    isRecoverMode ? "Connexion à mon École" : "Première Inscription",
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 10),

                  Text(
                    isRecoverMode
                        ? "Entrez l'ID de votre école et votre mot de passe"
                        : "Entrez l'ID fourni par l'administrateur",
                    style: const TextStyle(fontSize: 16, color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text("J'ai déjà un compte")),
                      ButtonSegment(value: false, label: Text("Nouvelle école")),
                    ],
                    selected: {isRecoverMode},
                    onSelectionChanged: (set) {
                      setState(() => isRecoverMode = set.first);
                      errorMessage = null;
                    },
                  ),

                  const SizedBox(height: 30),

                  TextField(
                    controller: idController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "ID de l'École",
                      hintText: "Ex: MAPENDO-7A3K9X2P",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Mot de Passe",
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.indigo,
                      ),
                      child: isLoading
                          ? const CircularProgressIndicator(color: Colors.indigo)
                          : Text(isRecoverMode ? "SE CONNECTER" : "ENREGISTRER L'ÉCOLE"),
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
