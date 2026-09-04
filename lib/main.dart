import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'network_resolver.dart';
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
// ⚡ CORRIGÉ — STOCKAGE LOCAL (SharedPreferences)
//
// La session n'a PLUS de durée fixe de 24h. La durée de travail
// autorisée (`durationValue`/`durationUnit`) est reçue du serveur à
// CHAQUE connexion réussie (voir `/verify_key`), et stockée ici avec
// l'horodatage de connexion. `isSessionExpired()` et
// `getRemainingSessionDuration()` calculent tous deux à partir de CES
// valeurs propres à la session en cours — jamais d'une constante.
// ====================================================================
class LocalStorageHelper {
  static const _kAccessKey = 'sub_access_key';
  static const _kSchoolCode = 'sub_school_code';
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

  // ⚡ NOUVEAU — durée de TRAVAIL autorisée, choisie par l'admin, reçue
  // du serveur à la connexion. Remplace l'ancienne constante fixe
  // `sessionDuration = Duration(hours: 24)`.
  static const _kSessionDurationValue = 'sub_session_duration_value';
  static const _kSessionDurationUnit = 'sub_session_duration_unit'; // 'days' | 'minutes'

  // ---------------- SESSION DE CONNEXION ----------------
  static Future<void> saveSession({
    required String accessKey,
    required String schoolCode,
    required List<String> sections,
    required String schoolName,
    required String accessType,
    String? assignedClasse,       // null/'' = toutes les classes
    String? activeSection,        // section actuellement affichée
    // ⚡ NOUVEAU — durée de travail autorisée pour CETTE connexion,
    // reçue du serveur (voir `/verify_key`). Repli sûr sur 1 jour si le
    // serveur ne les renvoie pas (ancien serveur non mis à jour).
    int durationValue = 1,
    String durationUnit = 'days',
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
    final int safeValue = durationValue < 1 ? 1 : durationValue;
    final String safeUnit = durationUnit == 'minutes' ? 'minutes' : 'days';
    await prefs.setInt(_kSessionDurationValue, safeValue);
    await prefs.setString(_kSessionDurationUnit, safeUnit);
  }

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

  static Future<void> saveActiveSection(String section) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveSection, section);
  }

  /// ⚡ NOUVEAU — durée de travail (jour/minute) enregistrée pour la
  /// session en cours, telle que reçue du serveur à la connexion.
  static Future<Duration> _getSessionDuration() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_kSessionDurationValue) ?? 1;
    final unit = prefs.getString(_kSessionDurationUnit) ?? 'days';
    return unit == 'minutes' ? Duration(minutes: value) : Duration(days: value);
  }

  /// ⚡ CORRIGÉ — n'utilise plus une constante fixe de 24h : compare le
  /// temps écoulé depuis la connexion à la durée de travail choisie par
  /// l'admin pour CETTE clé (reçue et stockée à la connexion).
  static Future<bool> isSessionExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final tsStr = prefs.getString(_kLoginTimestamp);
    if (tsStr == null) return true;
    final ts = DateTime.tryParse(tsStr);
    if (ts == null) return true;
    final duration = await _getSessionDuration();
    return DateTime.now().difference(ts) > duration;
  }

  /// ⚡ NOUVEAU — temps de travail RESTANT avant déconnexion
  /// automatique. Renvoie `Duration.zero` si déjà écoulé ou si aucune
  /// session n'est active. Utilisé par `scheduleSessionExpiry()` pour
  /// programmer la déconnexion exacte, y compris en cours
  /// d'utilisation (pas seulement au prochain lancement de l'app).
  static Future<Duration> getRemainingSessionDuration() async {
    final prefs = await SharedPreferences.getInstance();
    final tsStr = prefs.getString(_kLoginTimestamp);
    if (tsStr == null) return Duration.zero;
    final ts = DateTime.tryParse(tsStr);
    if (ts == null) return Duration.zero;
    final duration = await _getSessionDuration();
    final elapsed = DateTime.now().difference(ts);
    final remaining = duration - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
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
    await prefs.remove(_kSessionDurationValue);
    await prefs.remove(_kSessionDurationUnit);
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
// ⚡ NOUVEAU — DÉCONNEXION AUTOMATIQUE EN FIN DE TEMPS DE TRAVAIL
//
// À appeler dans `initState()` de CHAQUE écran accessible après
// connexion (paiement, discipline, inscription, autres frais). Le
// Timer renvoyé DOIT être annulé dans `dispose()` de l'écran appelant,
// pour éviter toute navigation après démontage du widget.
//
// Programme une déconnexion exacte à l'instant précis où le temps de
// travail alloué par l'admin (voir la clé d'accès) se termine — même
// si le sous-utilisateur est activement en train d'utiliser l'écran,
// pas seulement au prochain lancement de l'app.
// ====================================================================
Future<Timer?> scheduleSessionExpiry(BuildContext context) async {
  final remaining = await LocalStorageHelper.getRemainingSessionDuration();
  if (remaining <= Duration.zero) {
    // Déjà écoulé (ex: écran ouvert alors que le temps alloué est fini
    // entre-temps) : déconnexion immédiate.
    _forceLogoutExpired(context);
    return null;
  }
  return Timer(remaining, () => _forceLogoutExpired(context));
}

void _forceLogoutExpired(BuildContext context) async {
  await LocalStorageHelper.clearSession();
  await LocalStorageHelper.clearAllData();
  if (!context.mounted) return;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text("Temps de travail écoulé"),
      content: const Text(
        "Le temps que l'administrateur vous a accordé pour travailler "
            "avec cette clé est terminé. Contactez-le si vous avez besoin "
            "de continuer.",
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const KeyLoginScreen()),
                  (route) => false,
            );
          },
          child: const Text("Compris"),
        ),
      ],
    ),
  );
}

// ====================================================================
// ROUTAGE COMMUN
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

  // ⚡ CORRIGÉ — le texte reflète désormais qu'il s'agit du temps de
  // TRAVAIL écoulé, pas d'une clé devenue invalide (la clé, elle,
  // fonctionne toujours pour se reconnecter).
  void _showExpiredDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Temps de travail écoulé"),
        content: const Text(
          "Le temps que l'administrateur vous avait accordé pour "
              "travailler est terminé. Vous pouvez vous reconnecter avec "
              "la même clé si l'admin vous y autorise à nouveau, ou "
              "contactez-le pour une nouvelle clé.",
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
      // On résout automatiquement l'adresse à contacter : point
      // d'accès local de l'admin s'il est joignable, sinon internet.
      // Aucune saisie manuelle d'IP n'est jamais demandée.
      final base = await NetworkResolver.resolve();
      final response = await http.post(
        Uri.parse('$base/verify_key'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'key': key}),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['valid'] == true) {
          final schoolCode = data['school_code'] as String;
          final schoolName = data['school_name'] ?? 'Mon École';
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

          // ⚡ NOUVEAU — durée de TRAVAIL autorisée pour CETTE
          // connexion, envoyée par le serveur (voir `/verify_key`).
          // Repli sûr sur 1 jour si absente (ancien serveur).
          final int durationValue =
              (data['duration_value'] as num?)?.toInt() ?? 1;
          final String durationUnit =
          (data['duration_unit'] ?? 'days').toString();

          await LocalStorageHelper.clearAllData();

          await LocalStorageHelper.saveSession(
            accessKey: key,
            schoolCode: schoolCode,
            sections: sections,
            schoolName: schoolName,
            accessType: accessType,
            assignedClasse: assignedClasse,
            activeSection: activeSection,
            durationValue: durationValue,
            durationUnit: durationUnit,
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
      setState(() => errorMessage = "Clé invalide");
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
                  "basculer librement entre elles une fois connecté.\n\n"
                  "Le temps que vous pourrez passer à travailler après "
                  "connexion est défini par l'admin pour chaque clé.\n\n"
                  "Si vous êtes connecté au réseau WiFi créé par l'admin, "
                  "la connexion se fait automatiquement sans internet.",
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
// Sélecteur de section réutilisable
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

// ====================================================================
// ⚡ NOUVEAU — Petit badge affiché dans l'AppBar quand le réseau LOCAL
// (point d'accès de l'admin) est utilisé, pour informer visuellement le
// sous-utilisateur qu'il travaille sans internet, en parallèle avec les
// autres agents connectés au même point d'accès.
// ====================================================================
class LocalModeBadge extends StatelessWidget {
  final bool isLocal;
  const LocalModeBadge({super.key, required this.isLocal});

  @override
  Widget build(BuildContext context) {
    if (!isLocal) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(right: 4),
      child: Tooltip(
        message: "Connecté au point d'accès local (sans internet)",
        child: Icon(Icons.wifi_tethering, color: Colors.greenAccent),
      ),
    );
  }
}

// ==================== ÉCRAN PRINCIPAL CLIENT — PAIEMENT (clé PAY) ====================
class SubUserHomeScreen extends StatefulWidget {
  final String schoolCode;
  final List<String> assignedSections;
  final String initialSection;
  final String? assignedClasse;
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
  // ⚡ NOUVEAU
  bool isLocalMode = false;
  final searchController = TextEditingController();

  late String currentYear;
  late String activeSection;

  Map<String, dynamic> lastServerData = {};

  List<Map<String, dynamic>> pendingLocalTransactions = [];

  // ⚡ NOUVEAU — déconnexion automatique en fin de temps de travail.
  Timer? _expiryTimer;

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
    _initExpiryTimer();
  }

  Future<void> _initExpiryTimer() async {
    final timer = await scheduleSessionExpiry(context);
    if (mounted) {
      _expiryTimer = timer;
    } else {
      timer?.cancel();
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    searchController.dispose();
    super.dispose();
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

  Future<void> _fetchSchoolData({bool forceRefresh = false}) async {
    final bool hadDataAlready = eleves.isNotEmpty;
    if (!hadDataAlready) setState(() => isLoading = true);

    try {
      // Détection automatique local/internet.
      final base = await NetworkResolver.resolve(forceRefresh: forceRefresh);
      final response = await http
          .get(Uri.parse('$base/restore?school_code=${widget.schoolCode}'))
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
            isLocalMode = NetworkResolver.lastResolvedWasLocal;
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
      // Même résolution automatique pour l'enregistrement.
      final base = await NetworkResolver.resolve();
      final response = await http.post(
        Uri.parse('$base/record_payment'),
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
          // Badge "mode local" (point d'accès de l'admin).
          LocalModeBadge(isLocal: isLocalMode),
          SectionSwitcher(
            sections: widget.assignedSections,
            activeSection: activeSection,
            onChanged: _switchSection,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Recharger depuis le serveur",
            onPressed: () => _fetchSchoolData(forceRefresh: true),
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