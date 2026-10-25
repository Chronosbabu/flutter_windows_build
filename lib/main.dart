import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_state.dart';
import 'screens/school_home_screen.dart';
import 'screens/recovery_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EduPay School RDC',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: Provider.of<AppState>(context).isDarkMode
          ? ThemeMode.dark
          : ThemeMode.light,
      home: const SplashRouter(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ====================================================================
// ROUTEUR DE DÉMARRAGE
// ====================================================================
// ⚡ CORRECTIF : attend que AppState ait fini de lire SharedPreferences
// avant de décider où naviguer. Sans ça, schoolCode était toujours null
// au premier build → l'app affichait RecoveryScreen même si connecté,
// ou l'inverse selon le timing.
class SplashRouter extends StatelessWidget {
  const SplashRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    // En cours de chargement → spinner neutre
    if (!appState.initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Session valide → écran principal
    if (appState.schoolCode != null &&
        appState.schoolCode!.isNotEmpty &&
        appState.backupPassword != null &&
        appState.backupPassword!.isNotEmpty) {
      return const MainHomeScreen();
    }

    // Aucune session → connexion / première configuration
    return const RecoveryScreen();
  }
}

// ====================================================================
// ⚡ NOUVEAU — PORTE DE SÉCURITÉ (code de sécurité à l'entrée)
// ====================================================================
// Fonction OPTIONNELLE, désactivée par défaut : tant que l'utilisateur ne
// l'a pas autorisée depuis l'accueil, l'application se comporte
// exactement comme avant.
//
// Quand elle est autorisée :
//   - à chaque appui sur « Commencer la Gestion », le code de sécurité
//     de l'application (le même que celui demandé dans les paramètres)
//     est demandé ;
//   - code correct  -> l'application s'ouvre ;
//   - code incorrect -> rien ne s'ouvre ;
//   - pour désactiver la fonction, il faut aussi entrer le code.
//
// Le réglage est enregistré sur l'appareil, séparément pour chaque école
// (clé liée au code de l'école), et rien d'autre n'est modifié.
// Après 3 erreurs, la saisie est verrouillée 30 secondes.
// ====================================================================
class SecurityGate {
  static int _echecs = 0;
  static DateTime? _verrouJusqua;
  static const int _maxEssais = 3;
  static const int _verrouSecondes = 30;

  static String _cle(String? schoolCode) =>
      'exiger_code_securite_${(schoolCode ?? '').trim().toUpperCase()}';

  /// Vrai si l'utilisateur a autorisé la demande du code à l'entrée.
  static Future<bool> estActive(String? schoolCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_cle(schoolCode)) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Active ou désactive la demande du code. Retourne false si l'écriture
  /// a échoué (le réglage précédent reste alors en vigueur).
  static Future<bool> definir(String? schoolCode, bool valeur) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setBool(_cle(schoolCode), valeur);
    } catch (_) {
      return false;
    }
  }

  /// Retourne null si le code saisi est correct, sinon un message d'erreur.
  static String? verifier(String saisi, String? attendu) {
    final now = DateTime.now();
    if (_verrouJusqua != null && now.isBefore(_verrouJusqua!)) {
      final int secondes = _verrouJusqua!.difference(now).inSeconds + 1;
      return "Trop de tentatives. Réessayez dans $secondes seconde(s).";
    }
    if (attendu == null || attendu.isEmpty) {
      return "Aucun code de sécurité n'est défini pour cette école.";
    }
    if (saisi == attendu) {
      _echecs = 0;
      _verrouJusqua = null;
      return null;
    }
    _echecs++;
    if (_echecs >= _maxEssais) {
      _echecs = 0;
      _verrouJusqua = now.add(const Duration(seconds: _verrouSecondes));
      return "Code incorrect. Saisie verrouillée pendant "
          "$_verrouSecondes secondes.";
    }
    return "Code incorrect (${_maxEssais - _echecs} essai(s) restant(s)).";
  }
}

// Boîte de dialogue de saisie du code de sécurité.
// Retourne true uniquement si le code saisi est correct.
class _CodeSecuriteDialog extends StatefulWidget {
  final String titre;
  final String message;
  final String? codeAttendu;

  const _CodeSecuriteDialog({
    required this.titre,
    required this.message,
    required this.codeAttendu,
  });

  @override
  State<_CodeSecuriteDialog> createState() => _CodeSecuriteDialogState();
}

class _CodeSecuriteDialogState extends State<_CodeSecuriteDialog> {
  final TextEditingController _ctrl = TextEditingController();
  bool _masque = true;
  String? _erreur;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _valider() {
    final String? erreur =
    SecurityGate.verifier(_ctrl.text, widget.codeAttendu);
    if (erreur == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _erreur = erreur;
      _ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.lock_outline, color: Colors.indigo),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.titre)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            obscureText: _masque,
            enableSuggestions: false,
            autocorrect: false,
            onSubmitted: (_) => _valider(),
            decoration: InputDecoration(
              labelText: "Code de sécurité",
              border: const OutlineInputBorder(),
              errorText: _erreur,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                icon: Icon(
                    _masque ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _masque = !_masque),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("Annuler"),
        ),
        ElevatedButton(
          onPressed: _valider,
          child: const Text("Valider"),
        ),
      ],
    );
  }
}

// ====================================================================
// ÉCRAN D'ACCUEIL (après connexion)
// ====================================================================
class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  bool _codeExige = false;
  bool _occupe = false;

  @override
  void initState() {
    super.initState();
    _rafraichirEtat();
  }

  Future<void> _rafraichirEtat() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final bool actif = await SecurityGate.estActive(appState.schoolCode);
    if (mounted) setState(() => _codeExige = actif);
  }

  void _snack(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  // Bouton « Exiger le code de sécurité » (activer / désactiver).
  Future<void> _basculerCodeSecurite() async {
    if (_occupe) return;
    _occupe = true;
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final String? codeAttendu = appState.backupPassword;
      final String? schoolCode = appState.schoolCode;

      // Sécurité : on relit l'état réel enregistré.
      final bool actifMaintenant = await SecurityGate.estActive(schoolCode);
      if (!mounted) return;

      if (!actifMaintenant) {
        // ---- ACTIVATION ----
        if (codeAttendu == null || codeAttendu.isEmpty) {
          _snack(
              "Aucun code de sécurité n'est défini : impossible d'activer cette fonction.",
              color: Colors.red);
          return;
        }
        final bool? oui = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text("Exiger le code de sécurité ?"),
            content: const Text(
              "Voulez-vous autoriser le code de sécurité ?\n\n"
                  "Si vous répondez Oui, à chaque fois que vous appuierez sur "
                  "« Commencer la Gestion », le code de sécurité de "
                  "l'application vous sera demandé. Sans le bon code, "
                  "l'application ne s'ouvrira pas.\n\n"
                  "Vous pourrez désactiver cette demande plus tard (le code "
                  "sera alors demandé).",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Non"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Oui, autoriser"),
              ),
            ],
          ),
        );
        if (oui != true || !mounted) return;
        final bool ok = await SecurityGate.definir(schoolCode, true);
        if (!mounted) return;
        if (ok) {
          setState(() => _codeExige = true);
          _snack("🔒 Le code de sécurité sera demandé à chaque entrée.",
              color: Colors.green);
        } else {
          _snack("❌ Impossible d'enregistrer ce réglage.",
              color: Colors.red);
        }
      } else {
        // ---- DÉSACTIVATION (le code est exigé) ----
        final bool? correct = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _CodeSecuriteDialog(
            titre: "Désactiver la demande du code",
            message:
            "Entrez le code de sécurité pour ne plus le demander à "
                "l'entrée de l'application.",
            codeAttendu: codeAttendu,
          ),
        );
        if (correct != true || !mounted) return;
        final bool ok = await SecurityGate.definir(schoolCode, false);
        if (!mounted) return;
        if (ok) {
          setState(() => _codeExige = false);
          _snack("🔓 Le code de sécurité n'est plus demandé à l'entrée.");
        } else {
          _snack("❌ Impossible d'enregistrer ce réglage.",
              color: Colors.red);
        }
      }
    } finally {
      _occupe = false;
    }
  }

  // Bouton « Commencer la Gestion ».
  Future<void> _commencerLaGestion() async {
    if (_occupe) return;
    _occupe = true;
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final bool exige = await SecurityGate.estActive(appState.schoolCode);
      if (!mounted) return;

      if (exige) {
        final bool? correct = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _CodeSecuriteDialog(
            titre: "Code de sécurité",
            message:
            "Entrez le code de sécurité pour ouvrir l'application.",
            codeAttendu: appState.backupPassword,
          ),
        );
        // Code incorrect ou annulation : rien ne s'ouvre.
        if (correct != true || !mounted) return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SchoolHomeScreen()),
      );
    } finally {
      _occupe = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(appState.schoolName),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.indigo, Colors.teal],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ⚡ NOUVEAU — bouton tout en haut de la page de démarrage
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    icon: Icon(
                      _codeExige ? Icons.lock : Icons.lock_open,
                      size: 18,
                    ),
                    label: Text(
                      _codeExige
                          ? "Code de sécurité exigé ✓"
                          : "Exiger le code de sécurité",
                    ),
                    onPressed: _basculerCodeSecurite,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: _codeExige ? Colors.greenAccent : Colors.white70,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.school, size: 80, color: Colors.white),
                        const SizedBox(height: 20),
                        Text(
                          appState.schoolName,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Code : ${appState.schoolCode ?? ''}",
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 60),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.school, size: 28),
                          label: const Text(
                            "Commencer la Gestion",
                            style: TextStyle(fontSize: 18),
                          ),
                          onPressed: _commencerLaGestion,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 40, vertical: 18),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}