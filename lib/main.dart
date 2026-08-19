import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'screens/sub_user_discipline_screen.dart';
import 'screens/sub_user_inscription_screen.dart';
import 'screens/sub_user_autres_frais_screen.dart';

const String serverUrl = "https://jsinf.onrender.com";

// ==================== THEME GLOBAL (mode clair / sombre) ====================
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
          home: const SplashScreen(),
        );
      },
    );
  }
}

// ⚡⚡ Les 4 types d'accès qu'une clé peut porter. Doit rester en
// phase avec KEY_TYPES côté serveur et KeyAccessType côté admin_dashboard.
enum KeyAccessType { paiement, discipline, inscription, autresFrais }

KeyAccessType keyAccessTypeFromCode(String? code) {
  switch (code) {
    case 'DISC':
      return KeyAccessType.discipline;
    case 'INSC':
      return KeyAccessType.inscription;
    case 'AFR':
      return KeyAccessType.autresFrais;
    case 'PAY':
    default:
      return KeyAccessType.paiement;
  }
}

extension KeyAccessTypeX on KeyAccessType {
  String get code {
    switch (this) {
      case KeyAccessType.paiement:
        return 'PAY';
      case KeyAccessType.discipline:
        return 'DISC';
      case KeyAccessType.inscription:
        return 'INSC';
      case KeyAccessType.autresFrais:
        return 'AFR';
    }
  }

  String get label {
    switch (this) {
      case KeyAccessType.paiement:
        return 'Paiement des frais scolaires';
      case KeyAccessType.discipline:
        return 'Discipline';
      case KeyAccessType.inscription:
        return 'Inscription des élèves';
      case KeyAccessType.autresFrais:
        return 'Autres frais';
    }
  }
}

// ====================================================================
// STOCKAGE LOCAL (SharedPreferences)
// ====================================================================
// ⚡⚡⚡ NOUVEAU — une clé peut désormais couvrir PLUSIEURS sections/options
// à la fois (voir /generate_key et /verify_key côté serveur, qui renvoient
// une LISTE 'sections'). On persiste donc :
//   - la LISTE complète des sections accessibles avec cette clé
//   - la section ACTIVE (celle actuellement affichée à l'écran), que
//     l'utilisateur peut changer à tout moment via le sélecteur de section
//     présent dans chaque écran, sans avoir à se reconnecter.
class LocalStorageHelper {
  static const _kAccessKey = 'sub_access_key';
  static const _kSchoolCode = 'sub_school_code';
  // ⚡⚡⚡ NOUVEAU — remplace l'ancien _kSection (singulier) par une liste
  // encodée en JSON, plus la section actuellement sélectionnée par
  // l'utilisateur (bascule).
  static const _kSections = 'sub_assigned_sections';
  static const _kActiveSection = 'sub_active_section';
  static const _kAccessType = 'sub_access_type';   // 'PAY' | 'DISC' | 'INSC' | 'AFR'
  static const _kAssignedClasse = 'sub_assigned_classe'; // '' = toutes les classes
  static const _kSchoolName = 'sub_school_name';
  static const _kLoginTimestamp = 'sub_login_timestamp';
  static const _kCurrentYear = 'sub_current_year';
  static const _kCachedServerData = 'sub_cached_server_data';
  static const _kPendingPayments = 'sub_pending_payments';
  static const _kDarkMode = 'sub_dark_mode';

  static const Duration sessionDuration = Duration(hours: 24);

  // ---------------- SESSION DE CONNEXION ----------------
  static Future<void> saveSession({
    required String accessKey,
    required String schoolCode,
    required List<String> sections,
    required String schoolName,
    required String accessType,
    String? assignedClasse,       // null/'' = toutes les classes
    String? activeSection,        // section actuellement affichée
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessKey, accessKey);
    await prefs.setString(_kSchoolCode, schoolCode);
    await prefs.setString(_kSections, jsonEncode(sections));
    await prefs.setString(
      _kActiveSection,
      activeSection ?? (sections.isNotEmpty ? sections.first : ''),
    );
    await prefs.setString(_kSchoolName, schoolName);
    await prefs.setString(_kAccessType, accessType);
    await prefs.setString(_kAssignedClasse, assignedClasse ?? '');
    await prefs.setString(_kLoginTimestamp, DateTime.now().toIso8601String());
  }

  /// Renvoie la session en cours, ou null si aucune clé n'est enregistrée.
  /// 'sections' est une List<String>, tous les autres champs sont des
  /// String — d'où le type dynamique du Map.
  static Future<Map<String, dynamic>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_kAccessKey);
    if (key == null || key.isEmpty) return null;

    List<String> sections = [];
    final sectionsStr = prefs.getString(_kSections);
    if (sectionsStr != null && sectionsStr.isNotEmpty) {
      try {
        sections = (jsonDecode(sectionsStr) as List)
            .map((e) => e.toString())
            .toList();
      } catch (_) {
        sections = [];
      }
    }

    String activeSection = prefs.getString(_kActiveSection) ?? '';
    if (activeSection.isEmpty && sections.isNotEmpty) {
      activeSection = sections.first;
    }

    return {
      'accessKey': key,
      'schoolCode': prefs.getString(_kSchoolCode) ?? '',
      'sections': sections,
      'activeSection': activeSection,
      'schoolName': prefs.getString(_kSchoolName) ?? '',
      'accessType': prefs.getString(_kAccessType) ?? 'PAY',
      'assignedClasse': prefs.getString(_kAssignedClasse) ?? '',
    };
  }

  /// ⚡⚡⚡ NOUVEAU — change la section actuellement affichée (bascule),
  /// sans toucher au reste de la session ni exiger une reconnexion.
  static Future<void> saveActiveSection(String section) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveSection, section);
  }

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
    await prefs.remove(_kSections);
    await prefs.remove(_kActiveSection);
    await prefs.remove(_kSchoolName);
    await prefs.remove(_kAccessType);
    await prefs.remove(_kAssignedClasse);
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
// ⚡⚡⚡ NOUVEAU — ROUTAGE COMMUN : renvoie le bon écran d'accueil selon le
// type de la clé, en lui transmettant la LISTE complète des sections
// accessibles ainsi que la section actuellement active (bascule). Chaque
// écran reçoit désormais `assignedSections` (List<String>) au lieu d'une
// seule `assignedSection`, et gère lui-même son propre sélecteur de
// section quand `assignedSections.length > 1`.
// ====================================================================
Widget buildHomeForSession({
  required String accessKey,
  required String schoolCode,
  required String schoolName,
  required List<String> sections,
  required String activeSection,
  required String accessTypeCode,
  required String? assignedClasse, // null/'' = toutes les classes
  String? initialYear,
}) {
  final type = keyAccessTypeFromCode(accessTypeCode);
  final String? classe =
  (assignedClasse == null || assignedClasse.isEmpty) ? null : assignedClasse;
  final List<String> safeSections =
  sections.isNotEmpty ? sections : [activeSection.isNotEmpty ? activeSection : ''];
  final String safeActive =
  activeSection.isNotEmpty ? activeSection : safeSections.first;

  switch (type) {
    case KeyAccessType.discipline:
      return SubUserDisciplineScreen(
        schoolCode: schoolCode,
        schoolName: schoolName,
        assignedSections: safeSections,
        initialSection: safeActive,
        assignedClasse: classe,
        initialYear: initialYear,
      );
    case KeyAccessType.inscription:
      return SubUserInscriptionScreen(
        schoolCode: schoolCode,
        schoolName: schoolName,
        assignedSections: safeSections,
        initialSection: safeActive,
        assignedClasse: classe,
        initialYear: initialYear,
      );
    case KeyAccessType.autresFrais:
      return SubUserAutresFraisScreen(
        schoolCode: schoolCode,
        schoolName: schoolName,
        assignedSections: safeSections,
        initialSection: safeActive,
        assignedClasse: classe,
        initialYear: initialYear,
      );
    case KeyAccessType.paiement:
      return SubUserHomeScreen(
        schoolCode: schoolCode,
        assignedSections: safeSections,
        initialSection: safeActive,
        assignedClasse: classe,
        accessKey: accessKey,
        schoolName: schoolName,
        initialYear: initialYear,
      );
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
      await LocalStorageHelper.clearSession();
      _goToLogin(expired: true);
      return;
    }

    final List<String> sections =
    List<String>.from(session['sections'] as List? ?? const []);
    if (sections.isEmpty) {
      // Session corrompue / ancien format sans liste de sections : on force
      // une reconnexion propre plutôt que de planter sur une liste vide.
      await LocalStorageHelper.clearSession();
      _goToLogin(expired: false);
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => buildHomeForSession(
          accessKey: session['accessKey'] as String,
          schoolCode: session['schoolCode'] as String,
          schoolName: session['schoolName'] as String,
          sections: sections,
          activeSection: session['activeSection'] as String,
          accessTypeCode: session['accessType'] as String,
          assignedClasse: session['assignedClasse'] as String?,
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
          final schoolName = data['school_name'] ?? 'Mon École';
          // ⚡⚡⚡ NOUVEAU — le serveur multi-sections renvoie désormais une
          // LISTE 'sections'. On garde un repli sur l'ancien champ 'section'
          // (singulier) au cas où une clé provenant d'un ancien format
          // circulerait encore, pour ne jamais planter sur une liste vide.
          List<String> sections = [];
          if (data['sections'] is List) {
            sections = (data['sections'] as List)
                .map((s) => s.toString())
                .where((s) => s.isNotEmpty)
                .toList();
          }
          if (sections.isEmpty && data['section'] != null) {
            sections = [data['section'].toString()];
          }

          if (sections.isEmpty) {
            setState(() {
              errorMessage = "Clé invalide : aucune section associée";
              isLoading = false;
            });
            return;
          }

          final accessType = (data['type'] ?? 'PAY') as String;
          final assignedClasse = data['classe'] as String?;
          final String activeSection = sections.first;

          // On efface l'éventuel ancien cache d'une session précédente
          // avant de démarrer une nouvelle session.
          await LocalStorageHelper.clearAllData();

          await LocalStorageHelper.saveSession(
            accessKey: key,
            schoolCode: schoolCode,
            sections: sections,
            schoolName: schoolName,
            accessType: accessType,
            assignedClasse: assignedClasse,
            activeSection: activeSection,
          );

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => buildHomeForSession(
                  accessKey: key,
                  schoolCode: schoolCode,
                  schoolName: schoolName,
                  sections: sections,
                  activeSection: activeSection,
                  accessTypeCode: accessType,
                  assignedClasse: assignedClasse,
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
            const Text("Clé d'accès", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              "Une même clé donne accès à un seul usage (paiement, "
                  "discipline, inscription ou autres frais) mais peut "
                  "couvrir plusieurs sections/options — vous pourrez "
                  "basculer librement entre elles une fois connecté.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: keyController,
              decoration: const InputDecoration(
                labelText: "Clé fournie par l'Admin",
                border: OutlineInputBorder(),
                hintText: "Ex: MAPENDO*PAY*MAT+PRI*ALL*...",
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

// ====================================================================
// ⚡⚡⚡ NOUVEAU — Sélecteur de section réutilisable, affiché dans l'AppBar
// de chaque écran sous-utilisateur dès que la clé couvre plus d'une
// section. Un simple appui ouvre un menu déroulant listant toutes les
// sections accordées par la clé ; le choix déclenche `onChanged`.
// ====================================================================
class SectionSwitcher extends StatelessWidget {
  final List<String> sections;
  final String activeSection;
  final ValueChanged<String> onChanged;

  const SectionSwitcher({
    super.key,
    required this.sections,
    required this.activeSection,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (sections.length <= 1) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      tooltip: "Changer de section",
      initialValue: activeSection,
      onSelected: onChanged,
      itemBuilder: (ctx) => sections
          .map((s) => PopupMenuItem<String>(
        value: s,
        child: Row(
          children: [
            Icon(
              s == activeSection ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: s == activeSection ? Colors.indigo : Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(s),
          ],
        ),
      ))
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_horiz, color: Colors.white, size: 20),
            const SizedBox(width: 4),
            Text(
              activeSection,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== ÉCRAN PRINCIPAL CLIENT — PAIEMENT (clé PAY) ====================
class SubUserHomeScreen extends StatefulWidget {
  final String schoolCode;
  // ⚡⚡⚡ NOUVEAU — liste complète des sections accordées par la clé,
  // plus la section actuellement active (bascule).
  final List<String> assignedSections;
  final String initialSection;
  final String? assignedClasse; // null = toutes les classes de la section active
  final String accessKey;
  final String schoolName;
  final String? initialYear;

  const SubUserHomeScreen({
    super.key,
    required this.schoolCode,
    required this.assignedSections,
    required this.initialSection,
    this.assignedClasse,
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
  // ⚡⚡⚡ NOUVEAU — section actuellement affichée, modifiable via le
  // SectionSwitcher sans nécessiter de reconnexion.
  late String activeSection;

  Map<String, dynamic> lastServerData = {};

  List<Map<String, dynamic>> pendingLocalTransactions = [];

  final List<String> months = [
    'Septembre', 'Octobre', 'Novembre', 'Decembre',
    'Janvier', 'Fevrier', 'Mars', 'Avril', 'Mai', 'Juin'
  ];

  @override
  void initState() {
    super.initState();
    currentYear = widget.initialYear ?? '2025-2026';
    activeSection = widget.initialSection;
    searchController.addListener(_filterEleves);
    _bootstrap();
  }

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

    await _fetchSchoolData();
  }

  // ⚡⚡⚡ NOUVEAU — bascule vers une autre section accordée par la clé. Ne
  // nécessite aucune requête réseau (les données de toutes les sections
  // sont déjà en cache) : on ne fait que refiltrer localement.
  Future<void> _switchSection(String newSection) async {
    if (newSection == activeSection) return;
    setState(() {
      activeSection = newSection;
      isLoading = true;
    });
    await LocalStorageHelper.saveActiveSection(newSection);
    final built = _applyPendingAndBuildEleves(lastServerData);
    if (mounted) {
      setState(() {
        eleves = built;
        isLoading = false;
      });
      _filterEleves();
    }
  }

  // ⚡⚡ Filtre par la section ACTIVE (et par classe quand la clé est
  // verrouillée sur une classe précise — ce qui ne peut arriver que si la
  // clé ne couvre qu'une seule section).
  List<dynamic> _applyPendingAndBuildEleves(Map<String, dynamic> serverData) {
    final rawList = (serverData['history']?[currentYear]?['eleves'] ?? []) as List;
    final yearEleves = rawList
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) => e['section'] == activeSection)
        .where((e) =>
    widget.assignedClasse == null || e['classe'] == widget.assignedClasse)
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
        continue;
      }

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

  Future<void> _handlePayment(dynamic eleve, String mois, double amount) async {
    int index = months.indexOf(mois);
    if (index == -1) return;

    double remaining = amount;
    String currentMonth = mois;
    final String today = DateTime.now().toString().split(' ')[0];

    eleve['paid'] ??= <String, dynamic>{};
    eleve['transactions'] ??= <dynamic>[];

    while (remaining > 0 && index < months.length) {
      final required = _getRequiredForMonth(currentMonth, eleve['section'] ?? activeSection);
      final alreadyPaid = (eleve['paid'][currentMonth] ?? 0).toDouble();
      final needed = required - alreadyPaid;

      if (needed > 0) {
        final toAdd = remaining > needed ? needed : remaining;

        eleve['paid'][currentMonth] = alreadyPaid + toAdd;
        (eleve['transactions'] as List).add({
          'date': today,
          'mois': currentMonth,
          'amount': toAdd,
          'pending': true,
        });

        pendingLocalTransactions.add({
          'eleve_id': eleve['id'],
          'mois': currentMonth,
          'amount': toAdd,
          'date': today,
        });
        await LocalStorageHelper.savePendingPayments(pendingLocalTransactions);

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

  Future<void> _showMonthDetailDialog(dynamic eleve, String mois) async {
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          final required = _getRequiredForMonth(mois, eleve['section'] ?? activeSection);
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
    final String titleSuffix = widget.assignedClasse != null
        ? "$activeSection - ${widget.assignedClasse}"
        : activeSection;

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.schoolName} - $titleSuffix ($currentYear)"),
        backgroundColor: Colors.indigo,
        actions: [
          // ⚡⚡⚡ NOUVEAU — bascule entre sections (visible uniquement si la
          // clé couvre plus d'une section).
          SectionSwitcher(
            sections: widget.assignedSections,
            activeSection: activeSection,
            onChanged: _switchSection,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Recharger depuis le serveur",
            onPressed: _fetchSchoolData,
          ),
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
                  "Élèves ($activeSection) : ${filteredEleves.length}",
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
// Commun aux 4 types d'accès (chaque écran d'accueil y renvoie).
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

    await LocalStorageHelper.clearSession();
    await LocalStorageHelper.clearAllData();

    if (!mounted) return;
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