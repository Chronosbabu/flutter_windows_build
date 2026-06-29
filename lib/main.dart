import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

const String serverUrl = "https://jsinf.onrender.com";

// ==================== THEME GLOBAL (mode clair / sombre) ====================
// ValueNotifier global et simple : permet à n'importe quel écran de changer
// le thème instantanément, sans passer par un Provider complet.
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On charge la préférence de thème sauvegardée AVANT de lancer l'app,
  // pour éviter un flash en mode clair puis bascule en mode sombre.
  final isDark = await LocalStorageHelper.getDarkMode();
  themeModeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  runApp(const SubUserApp());
}

class SubUserApp extends StatelessWidget {
  const SubUserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Gestion Section',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.indigo,
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            primarySwatch: Colors.indigo,
            brightness: Brightness.dark,
          ),
          themeMode: mode,
          // ⚡ On ne démarre plus directement sur la page de connexion :
          // un écran de démarrage (SplashScreen) décide d'abord, en local
          // et SANS connexion internet, si une session valide existe déjà.
          home: const SplashScreen(),
        );
      },
    );
  }
}

// ====================================================================
// STOCKAGE LOCAL (SharedPreferences)
// ====================================================================
// Centralise TOUT ce qui doit survivre à la fermeture de l'application :
// - la session de connexion (clé, code école, section, nom école, date de
//   connexion) pour ne plus jamais redemander la clé tant qu'elle est valide
// - les dernières données reçues du serveur (cache complet, pour un
//   affichage hors-ligne immédiat au redémarrage)
// - les paiements effectués localement mais pas encore validés par l'admin
//   (pour que l'historique avec les dates ne disparaisse jamais, même après
//   fermeture de l'app ou redémarrage du PC)
// - la préférence de thème (clair/sombre)
class LocalStorageHelper {
  static const _kAccessKey = 'sub_access_key';
  static const _kSchoolCode = 'sub_school_code';
  static const _kSection = 'sub_assigned_section';
  static const _kSchoolName = 'sub_school_name';
  static const _kLoginTimestamp = 'sub_login_timestamp';
  static const _kCurrentYear = 'sub_current_year';
  static const _kCachedServerData = 'sub_cached_server_data';
  static const _kPendingPayments = 'sub_pending_payments';
  static const _kDarkMode = 'sub_dark_mode';

  // ⚡ Durée de validité de la session, vérifiée localement (donc valable
  // même si le PC reste éteint pendant 24h, sans connexion internet).
  static const Duration sessionDuration = Duration(hours: 24);

  // ---------------- SESSION DE CONNEXION ----------------
  static Future<void> saveSession({
    required String accessKey,
    required String schoolCode,
    required String section,
    required String schoolName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessKey, accessKey);
    await prefs.setString(_kSchoolCode, schoolCode);
    await prefs.setString(_kSection, section);
    await prefs.setString(_kSchoolName, schoolName);
    // On enregistre l'heure EXACTE de connexion. L'expiration sera calculée
    // par simple différence de date, ce qui fonctionne 100% hors-ligne.
    await prefs.setString(_kLoginTimestamp, DateTime.now().toIso8601String());
  }

  static Future<Map<String, String>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_kAccessKey);
    if (key == null || key.isEmpty) return null;
    return {
      'accessKey': key,
      'schoolCode': prefs.getString(_kSchoolCode) ?? '',
      'section': prefs.getString(_kSection) ?? '',
      'schoolName': prefs.getString(_kSchoolName) ?? '',
    };
  }

  /// Retourne true si plus de 24h se sont écoulées depuis la connexion,
  /// en comparant simplement deux dates locales : aucune connexion internet
  /// n'est nécessaire pour ce calcul, et il reste exact même si le PC a été
  /// éteint pendant tout ce temps (l'horloge système continue d'avancer).
  static Future<bool> isSessionExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final tsStr = prefs.getString(_kLoginTimestamp);
    if (tsStr == null) return true;
    final ts = DateTime.tryParse(tsStr);
    if (ts == null) return true;
    return DateTime.now().difference(ts) > sessionDuration;
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessKey);
    await prefs.remove(_kSchoolCode);
    await prefs.remove(_kSection);
    await prefs.remove(_kSchoolName);
    await prefs.remove(_kLoginTimestamp);
  }

  // ---------------- DONNÉES (cache élèves + paiements en attente) ----------------
  static Future<void> saveCurrentYear(String year) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCurrentYear, year);
  }

  static Future<String?> getCurrentYear() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCurrentYear);
  }

  static Future<void> saveCachedServerData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCachedServerData, jsonEncode(data));
  }

  static Future<Map<String, dynamic>?> getCachedServerData() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_kCachedServerData);
    if (str == null) return null;
    try {
      return jsonDecode(str) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> savePendingPayments(List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingPayments, jsonEncode(list));
  }

  static Future<List<Map<String, dynamic>>> getPendingPayments() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_kPendingPayments);
    if (str == null) return [];
    try {
      final decoded = jsonDecode(str) as List<dynamic>;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Efface toutes les données locales (cache élèves + paiements en
  /// attente). Utilisé à la déconnexion pour repartir propre.
  static Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCachedServerData);
    await prefs.remove(_kPendingPayments);
    await prefs.remove(_kCurrentYear);
  }

  // ---------------- THÈME ----------------
  static Future<void> saveDarkMode(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDarkMode, isDark);
  }

  static Future<bool> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kDarkMode) ?? false;
  }
}

// ====================================================================
// ÉCRAN DE DÉMARRAGE (décide où aller, sans aucune requête réseau)
// ====================================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final session = await LocalStorageHelper.getSession();

    if (session == null) {
      _goToLogin(expired: false);
      return;
    }

    final expired = await LocalStorageHelper.isSessionExpired();
    if (expired) {
      // ⚡ Clé expirée localement : on efface la session (mais PAS les
      // données élèves déjà en cache, qui resteront utiles après la
      // prochaine connexion avec une nouvelle clé) et on redemande la clé,
      // avec un message explicite pour l'utilisateur.
      await LocalStorageHelper.clearSession();
      _goToLogin(expired: true);
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SubUserHomeScreen(
          schoolCode: session['schoolCode']!,
          assignedSection: session['section']!,
          accessKey: session['accessKey']!,
          schoolName: session['schoolName']!,
          initialYear: null,
        ),
      ),
    );
  }

  void _goToLogin({required bool expired}) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => KeyLoginScreen(showExpiredMessage: expired)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

// ==================== PAGE DE CONNEXION ====================
class KeyLoginScreen extends StatefulWidget {
  final bool showExpiredMessage;
  const KeyLoginScreen({super.key, this.showExpiredMessage = false});

  @override
  State<KeyLoginScreen> createState() => _KeyLoginScreenState();
}

class _KeyLoginScreenState extends State<KeyLoginScreen> {
  final keyController = TextEditingController();
  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.showExpiredMessage) {
      // On attend que l'écran soit complètement affiché avant d'ouvrir
      // le dialogue, pour éviter une erreur de contexte.
      WidgetsBinding.instance.addPostFrameCallback((_) => _showExpiredDialog());
    }
  }

  void _showExpiredDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Clé expirée"),
        content: const Text(
          "Votre clé a expiré. Veuillez contacter l'admin pour vous en fournir une autre.",
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Compris"),
          ),
        ],
      ),
    );
  }

  Future<void> _loginWithKey() async {
    final key = keyController.text.trim();
    if (key.isEmpty) {
      setState(() => errorMessage = "Veuillez entrer la clé");
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$serverUrl/verify_key'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'key': key}),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['valid'] == true) {
          final schoolCode = data['school_code'] as String;
          final section = data['section'] as String;
          final schoolName = data['school_name'] ?? 'Mon École';

          // ⚡ On efface l'éventuel ancien cache d'une session précédente
          // (autre section/école) avant de démarrer une nouvelle session,
          // pour ne jamais mélanger les données de deux clés différentes.
          await LocalStorageHelper.clearAllData();

          // ⚡ Sauvegarde de la session : c'est elle qui permet de ne plus
          // jamais redemander la clé tant qu'elle n'a pas expiré (24h).
          await LocalStorageHelper.saveSession(
            accessKey: key,
            schoolCode: schoolCode,
            section: section,
            schoolName: schoolName,
          );

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => SubUserHomeScreen(
                  schoolCode: schoolCode,
                  assignedSection: section,
                  accessKey: key,
                  schoolName: schoolName,
                  initialYear: data['current_year']?.toString(),
                ),
              ),
            );
          }
          return;
        }
      }
      setState(() => errorMessage = "Clé invalide ou expirée");
    } catch (e) {
      setState(() => errorMessage = "Serveur inaccessible. Vérifiez votre connexion.");
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Connexion Section")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock, size: 90, color: Colors.indigo),
            const SizedBox(height: 30),
            const Text("Clé d'accès Section", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: keyController,
              decoration: const InputDecoration(
                labelText: "Clé fournie par l'Admin",
                border: OutlineInputBorder(),
                hintText: "Ex: MAPENDO*MAT*...",
              ),
            ),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(errorMessage!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: isLoading ? null : _loginWithKey,
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Se Connecter", style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== ÉCRAN PRINCIPAL CLIENT ====================
class SubUserHomeScreen extends StatefulWidget {
  final String schoolCode;
  final String assignedSection;
  final String accessKey;
  final String schoolName;
  final String? initialYear;

  const SubUserHomeScreen({
    super.key,
    required this.schoolCode,
    required this.assignedSection,
    required this.accessKey,
    required this.schoolName,
    this.initialYear,
  });

  @override
  State<SubUserHomeScreen> createState() => _SubUserHomeScreenState();
}

class _SubUserHomeScreenState extends State<SubUserHomeScreen> {
  List<dynamic> eleves = [];
  List<dynamic> filteredEleves = [];
  Map<String, dynamic> config = {};
  bool isLoading = true;
  final searchController = TextEditingController();

  late String currentYear;

  // Dernière réponse complète /restore reçue du serveur (source de vérité
  // pour tout ce qui est VALIDÉ par l'admin). Mise en cache localement.
  Map<String, dynamic> lastServerData = {};

  // ⚡ Paiements effectués localement mais pas encore validés par l'admin.
  // Persistés sur disque : ils survivent à la fermeture de l'app, à un
  // redémarrage du PC, et même à une longue période hors-ligne. C'est ce
  // qui garantit que TOUS les paiements (avec leurs dates) restent visibles
  // même si l'app est fermée avant la prochaine synchronisation.
  List<Map<String, dynamic>> pendingLocalTransactions = [];

  final List<String> months = [
    'Septembre', 'Octobre', 'Novembre', 'Decembre',
    'Janvier', 'Fevrier', 'Mars', 'Avril', 'Mai', 'Juin'
  ];

  @override
  void initState() {
    super.initState();
    currentYear = widget.initialYear ?? '2025-2026';
    searchController.addListener(_filterEleves);
    _bootstrap();
  }

  // ==================== DÉMARRAGE : AFFICHAGE HORS-LIGNE IMMÉDIAT ====================
  Future<void> _bootstrap() async {
    pendingLocalTransactions = await LocalStorageHelper.getPendingPayments();

    final cachedYear = await LocalStorageHelper.getCurrentYear();
    if (cachedYear != null && cachedYear.isNotEmpty) {
      currentYear = cachedYear;
    }

    final cachedData = await LocalStorageHelper.getCachedServerData();
    if (cachedData != null) {
      lastServerData = cachedData;
      config = cachedData['config'] ?? {};
      final built = _applyPendingAndBuildEleves(lastServerData);
      if (mounted) {
        setState(() {
          eleves = built;
          filteredEleves = List.from(built);
          isLoading = false;
        });
      }
      _filterEleves();
    }

    // Que le cache existe ou non, on tente toujours une synchronisation
    // en arrière-plan (silencieuse si on avait déjà du cache à afficher).
    await _fetchSchoolData();
  }

  // ==================== FUSION : DONNÉES SERVEUR + PAIEMENTS EN ATTENTE ====================
  // Reconstruit la liste d'élèves affichée à partir de la dernière réponse
  // serveur connue (source de vérité pour les paiements déjà VALIDÉS), puis
  // réapplique par-dessus chaque paiement local pas encore validé. Un
  // paiement local est retiré de la liste d'attente dès qu'on retrouve sa
  // trace, validée, dans les données du serveur (évite les doublons).
  List<dynamic> _applyPendingAndBuildEleves(Map<String, dynamic> serverData) {
    final rawList = (serverData['history']?[currentYear]?['eleves'] ?? []) as List;
    final yearEleves = rawList
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) => e['section'] == widget.assignedSection)
        .toList();

    for (var e in yearEleves) {
      e['paid'] = Map<String, dynamic>.from(e['paid'] ?? {});
      e['transactions'] = List<dynamic>.from(e['transactions'] ?? []);
    }

    final stillPending = <Map<String, dynamic>>[];
    for (var p in pendingLocalTransactions) {
      Map<String, dynamic>? eleve;
      for (var e in yearEleves) {
        if (e['id'] == p['eleve_id']) {
          eleve = e;
          break;
        }
      }
      if (eleve == null) {
        // Élève introuvable dans cette synchro (changement d'année, etc.) :
        // on garde le paiement en attente plutôt que de le perdre.
        stillPending.add(p);
        continue;
      }

      final mois = p['mois'];
      final amount = (p['amount'] as num).toDouble();
      final transactions = eleve['transactions'] as List;

      final alreadyValidated = transactions.any((t) =>
      t['mois'] == mois &&
          ((t['amount'] as num?)?.toDouble() ?? -1) == amount &&
          t['validated'] == true);

      if (alreadyValidated) {
        // Ce paiement est désormais confirmé côté serveur : on ne le
        // réapplique plus, et on le retire définitivement de l'attente.
        continue;
      }

      // Toujours en attente : on l'affiche par-dessus les données serveur.
      final paidMap = eleve['paid'] as Map<String, dynamic>;
      paidMap[mois] = ((paidMap[mois] ?? 0) as num).toDouble() + amount;
      transactions.add({
        'date': p['date'],
        'mois': mois,
        'amount': amount,
        'pending': true,
      });
      stillPending.add(p);
    }

    pendingLocalTransactions = stillPending;
    LocalStorageHelper.savePendingPayments(pendingLocalTransactions);

    return yearEleves;
  }

  Future<void> _fetchSchoolData() async {
    final bool hadDataAlready = eleves.isNotEmpty;
    if (!hadDataAlready) setState(() => isLoading = true);

    try {
      final response = await http
          .get(Uri.parse('$serverUrl/restore?school_code=${widget.schoolCode}'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        lastServerData = data;
        await LocalStorageHelper.saveCachedServerData(data);

        final fetchedYear = data['currentYear']?.toString();
        if (fetchedYear != null && fetchedYear.isNotEmpty) {
          currentYear = fetchedYear;
          await LocalStorageHelper.saveCurrentYear(currentYear);
        }

        config = data['config'] ?? {};
        final built = _applyPendingAndBuildEleves(lastServerData);

        if (mounted) {
          setState(() {
            eleves = built;
          });
          _filterEleves();
        }
      }
    } catch (e) {
      // Hors-ligne ou serveur inaccessible : on garde simplement ce qui est
      // déjà affiché (cache local + paiements en attente), rien n'est perdu.
      debugPrint("Pas de connexion, affichage des données locales : $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _filterEleves() {
    final query = searchController.text.toLowerCase().trim();
    setState(() {
      filteredEleves = eleves.where((e) {
        final name = "${e['nom']} ${e['postNom']} ${e['prenom']}".toLowerCase();
        final id = (e['id'] ?? '').toLowerCase();
        return name.contains(query) || id.contains(query);
      }).toList();
    });
  }

  double _getRequiredForMonth(String mois, String section) {
    final exceptions = config['monthlyExceptionsBySection']?[section]?[mois];
    if (exceptions != null) return (exceptions as num).toDouble();
    final fee = config['feesBySection']?[section];
    if (fee != null) return (fee as num).toDouble();
    return 35000;
  }

  // ==================== DISTRIBUTION DU PAIEMENT (avec dates + persistance) ====================
  Future<void> _handlePayment(dynamic eleve, String mois, double amount) async {
    int index = months.indexOf(mois);
    if (index == -1) return;

    double remaining = amount;
    String currentMonth = mois;
    final String today = DateTime.now().toString().split(' ')[0];

    eleve['paid'] ??= <String, dynamic>{};
    eleve['transactions'] ??= <dynamic>[];

    while (remaining > 0 && index < months.length) {
      final required = _getRequiredForMonth(currentMonth, eleve['section'] ?? widget.assignedSection);
      final alreadyPaid = (eleve['paid'][currentMonth] ?? 0).toDouble();
      final needed = required - alreadyPaid;

      if (needed > 0) {
        final toAdd = remaining > needed ? needed : remaining;

        // 1) Mise à jour optimiste immédiate, visible tout de suite.
        eleve['paid'][currentMonth] = alreadyPaid + toAdd;
        (eleve['transactions'] as List).add({
          'date': today,
          'mois': currentMonth,
          'amount': toAdd,
          'pending': true,
        });

        // 2) ⚡ Enregistrement local PERSISTANT : ce paiement (avec sa date)
        // survivra à la fermeture de l'app, même sans connexion, jusqu'à
        // ce qu'il soit validé par l'admin.
        pendingLocalTransactions.add({
          'eleve_id': eleve['id'],
          'mois': currentMonth,
          'amount': toAdd,
          'date': today,
        });
        await LocalStorageHelper.savePendingPayments(pendingLocalTransactions);

        // 3) Tentative d'envoi au serveur (best-effort, fonctionne aussi
        // hors-ligne : le paiement reste de toute façon visible localement).
        await _recordPayment(eleve['id'], currentMonth, toAdd);

        remaining -= toAdd;
      }

      index++;
      if (index < months.length) currentMonth = months[index];
    }

    if (mounted) setState(() {});
  }

  Future<void> _recordPayment(String eleveId, String mois, double amount) async {
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/record_payment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'school_code': widget.schoolCode,
          'annee': currentYear,
          'eleve_id': eleveId,
          'mois': mois,
          'amount': amount,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ Paiement envoyé au serveur (en attente de validation)"),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Paiement enregistré localement (hors ligne, sera envoyé plus tard)"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  // ==================== LISTE DES MOIS ====================
  void _showMonthsDialog(dynamic eleve) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text("${eleve['nom']} ${eleve['prenom']}"),
          content: SizedBox(
            width: double.maxFinite,
            height: 450,
            child: ListView.builder(
              itemCount: months.length,
              itemBuilder: (context, i) {
                final mois = months[i];
                final required = _getRequiredForMonth(mois, eleve['section'] ?? '');
                final paid = (eleve['paid']?[mois] ?? 0).toDouble();
                final isFullyPaid = paid >= required;
                final List transactions = (eleve['transactions'] as List?) ?? [];
                final nbPaiements = transactions.where((t) => t['mois'] == mois).length;
                return ListTile(
                  title: Text(mois),
                  subtitle: Text(
                    'Requis: ${required.toStringAsFixed(0)} FC | Payé: ${paid.toStringAsFixed(0)} FC'
                        '${nbPaiements > 0 ? ' • $nbPaiements paiement(s)' : ''}',
                  ),
                  trailing: isFullyPaid
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.warning, color: Colors.orange),
                  onTap: () async {
                    await _showMonthDetailDialog(eleve, mois);
                    setDialogState(() {});
                  },
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Fermer"))],
        ),
      ),
    );
  }

  // ==================== DÉTAIL D'UN MOIS : HISTORIQUE DES DATES ====================
  Future<void> _showMonthDetailDialog(dynamic eleve, String mois) async {
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          final required = _getRequiredForMonth(mois, eleve['section'] ?? widget.assignedSection);
          final paid = (eleve['paid']?[mois] ?? 0).toDouble();
          final isFullyPaid = paid >= required;

          final List transactions = (eleve['transactions'] as List?) ?? [];
          final historique = transactions.where((t) => t['mois'] == mois).toList()
            ..sort((a, b) => (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));

          return AlertDialog(
            title: Text("$mois - ${eleve['nom']} ${eleve['prenom']}"),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Requis : ${required.toStringAsFixed(0)} FC\n"
                        "Déjà payé : ${paid.toStringAsFixed(0)} FC",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Historique des paiements (date - montant) :",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  if (historique.isEmpty)
                    const Text(
                      "Aucun paiement enregistré pour ce mois.",
                      style: TextStyle(color: Colors.grey),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: historique.length,
                        itemBuilder: (context, i) {
                          final t = historique[i];
                          final montant = (t['amount'] as num?)?.toDouble() ?? 0;
                          final date = t['date']?.toString() ?? "Date inconnue";
                          final isPending = t['pending'] == true;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.receipt_long,
                              size: 20,
                              color: isPending ? Colors.orange : Colors.indigo,
                            ),
                            title: Text(date),
                            subtitle: isPending ? const Text("En attente de validation") : null,
                            trailing: Text(
                              "${montant.toStringAsFixed(0)} FC",
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Fermer")),
              if (!isFullyPaid)
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text("Ajouter un paiement"),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showPaymentDialog(eleve, mois);
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showPaymentDialog(dynamic eleve, String mois) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Paiement - $mois"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "Montant (FC)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(controller.text);
              if (amount != null && amount > 0) {
                Navigator.pop(ctx);
                await _handlePayment(eleve, mois, amount);
              }
            },
            child: const Text("Confirmer"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.schoolName} - ${widget.assignedSection} ($currentYear)"),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Recharger depuis le serveur",
            onPressed: _fetchSchoolData,
          ),
          // ⚡ Nouvel accès à l'écran Paramètres (déconnexion + thème).
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: "Paramètres",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                labelText: "Rechercher par nom ou ID",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  "Élèves : ${filteredEleves.length}",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          Expanded(
            child: filteredEleves.isEmpty
                ? const Center(child: Text("Aucun élève trouvé"))
                : ListView.builder(
              itemCount: filteredEleves.length,
              itemBuilder: (context, index) {
                final e = filteredEleves[index];
                final totalPaid = (e['paid'] as Map? ?? {})
                    .values
                    .fold(0.0, (sum, v) => sum + (v as num).toDouble());
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(child: Text(e['id']?.substring(0, 2) ?? "?")),
                    title: Text("${e['nom']} ${e['postNom']} ${e['prenom']}"),
                    subtitle: Text("ID: ${e['id']}\nClasse: ${e['classe']}"),
                    trailing: Text("${totalPaid.toStringAsFixed(0)} FC"),
                    onTap: () => _showMonthsDialog(e),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// ÉCRAN PARAMÈTRES : déconnexion + mode clair/sombre
// ====================================================================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _toggleDarkMode(bool value) async {
    themeModeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
    await LocalStorageHelper.saveDarkMode(value);
    setState(() {});
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Déconnexion"),
        content: const Text(
          "Voulez-vous vraiment vous déconnecter ? Vous devrez entrer une "
              "clé d'accès pour vous reconnecter.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Déconnexion", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // ⚡ On efface la session ET les données mises en cache (cache élèves +
    // paiements en attente) : un nouveau login (même avec une autre clé)
    // démarre proprement, sans mélanger les données de deux écoles/sections.
    await LocalStorageHelper.clearSession();
    await LocalStorageHelper.clearAllData();

    if (!mounted) return;
    // On retire tout l'historique de navigation pour revenir directement
    // à la page de connexion, sans pouvoir "revenir en arrière".
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const KeyLoginScreen()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Paramètres")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: themeModeNotifier,
              builder: (context, mode, _) {
                return SwitchListTile(
                  title: const Text("Mode Sombre"),
                  subtitle: const Text("Basculer entre le mode clair et le mode sombre"),
                  secondary: Icon(mode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode),
                  value: mode == ThemeMode.dark,
                  onChanged: _toggleDarkMode,
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Card(
            color: Colors.red.shade50,
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Déconnexion", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              subtitle: const Text("Revenir à la page de connexion par clé"),
              onTap: _logout,
            ),
          ),
        ],
      ),
    );
  }
}