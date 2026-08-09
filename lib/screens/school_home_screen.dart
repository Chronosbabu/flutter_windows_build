import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../frais_scolaires.dart';
import '../app_state.dart';
import 'enregistrer_eleve_screen.dart';
import 'paiement_eleve_screen.dart';
import 'repartition_screen.dart';
import 'settings_screen.dart';
import 'student_list_screen.dart';
import 'admin_dashboard_screen.dart';
import 'recus_screen.dart';

class SchoolHomeScreen extends StatefulWidget {
  const SchoolHomeScreen({super.key});

  @override
  State<SchoolHomeScreen> createState() => _SchoolHomeScreenState();
}

class _SchoolHomeScreenState extends State<SchoolHomeScreen> {
  late FraisScolaires fraisScolaires;

  // ⚡ NOUVEAU : évite de ré-écraser schoolCode à chaque frame/build tant
  // que le chargement initial n'est pas terminé.
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    fraisScolaires = FraisScolaires();
    _loadData();
  }

  // ====================================================================
  // ⚡ CORRIGÉ — Réconciliation propre entre AppState.schoolCode
  // (source de vérité, définie via RecoveryScreen / SettingsScreen et
  // stockée dans SharedPreferences) et FraisScolaires.schoolCode
  // (chargé depuis le fichier JSON local school_fees_data.json).
  //
  // AVANT : on assignait fraisScolaires.schoolCode = appState.schoolCode
  // PUIS on appelait loadData(), qui écrasait immédiatement cette valeur
  // avec ce qu'il y avait dans le JSON local (potentiellement null si le
  // fichier vient d'un ancien build, ou différent si le JSON a été
  // transféré depuis un autre appareil). Rien n'était jamais réconcilié
  // ni réécrit sur disque, donc le mobile-money badge (qui lit
  // fraisScolaires.schoolCode) et le backup serveur (qui lit
  // appState.schoolCode) pouvaient diverger silencieusement d'une
  // session à l'autre — un scénario plausible après un transfert de
  // fichiers Mac → clé USB → PC.
  //
  // MAINTENANT : on charge d'abord le JSON local, PUIS on applique une
  // règle claire :
  //   - Si AppState a un code (cas normal : l'utilisateur s'est déjà
  //     connecté/activé via RecoveryScreen sur CET appareil), c'est LUI
  //     qui fait autorité, et on le réécrit dans le JSON local pour que
  //     tout reste synchronisé la prochaine fois.
  //   - Sinon, si le JSON local avait un code (ancien install, ou
  //     restauration manuelle), on le remonte vers AppState pour que le
  //     prochain backup/restore utilise le bon code.
  // ====================================================================
  Future<void> _loadData() async {
    final appState = Provider.of<AppState>(context, listen: false);

    // 1. Charger d'abord les données locales telles quelles (sans rien
    //    imposer avant), pour connaître le school_code réellement
    //    présent dans le fichier JSON de CET appareil.
    await fraisScolaires.loadData();

    final localCode = fraisScolaires.schoolCode;
    final stateCode = appState.schoolCode;

    if (stateCode != null && stateCode.isNotEmpty) {
      // AppState fait autorité (cas normal).
      if (localCode != stateCode) {
        fraisScolaires.schoolCode = stateCode;
        await fraisScolaires.saveData(); // ⚡ on persiste la correction
      }
    } else if (localCode != null && localCode.isNotEmpty) {
      // Cas de secours : le JSON local avait un code mais AppState non
      // (ex: ancien install, ou fichier restauré manuellement).
      await appState.setSchoolCode(localCode);
    }

    _initialLoadDone = true;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    // ⚡ On ne réaffecte plus schoolCode à chaque build sans persister :
    // seulement une fois le chargement initial terminé, et seulement si
    // AppState a effectivement une valeur (source de vérité). On
    // persiste aussi le changement pour éviter toute divergence future.
    if (_initialLoadDone &&
        appState.schoolCode != null &&
        appState.schoolCode!.isNotEmpty &&
        fraisScolaires.schoolCode != appState.schoolCode) {
      fraisScolaires.schoolCode = appState.schoolCode;
      fraisScolaires.saveData();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "${appState.schoolName} - ${fraisScolaires.currentYear}",
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    SettingsScreen(fraisScolaires: fraisScolaires),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ==================== CARTE RÉSUMÉ ====================
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      'Année : ${fraisScolaires.currentYear}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Élèves : ${fraisScolaires.currentData.eleves.length}',
                    ),
                    Text(
                      'Total Collecté : '
                          '${fraisScolaires.getYearTotalCollected().toStringAsFixed(0)} FC',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ==================== GRILLE DES BOUTONS ====================
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.1,
              children: [
                _buildCard(
                  Icons.person_add,
                  "Ajouter Élève",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EnregistrerEleveScreen(
                          fraisScolaires: fraisScolaires),
                    ),
                  ),
                ),
                _buildCard(
                  Icons.payment,
                  "Paiements",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PaiementEleveScreen(
                          fraisScolaires: fraisScolaires),
                    ),
                  ),
                ),
                _buildCard(
                  Icons.list_alt,
                  "Registre des Élèves",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StudentListScreen(
                          fraisScolaires: fraisScolaires),
                    ),
                  ),
                ),
                _buildCard(
                  Icons.picture_as_pdf,
                  "Rapport PDF",
                      () => _showReportDialog(context),
                ),
                _buildCard(
                  Icons.share,
                  "Répartition",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RepartitionScreen(
                          fraisScolaires: fraisScolaires),
                    ),
                  ),
                ),
                _buildCard(
                  Icons.admin_panel_settings,
                  "Admin Dashboard",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminDashboardScreen(
                          fraisScolaires: fraisScolaires),
                    ),
                  ),
                ),
                // ⚡ Historique des Reçus
                _buildCard(
                  Icons.receipt_long,
                  "Historique Reçus",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RecusScreen(fraisScolaires: fraisScolaires),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 50, color: Colors.indigo),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== DIALOGUE RAPPORT PDF ====================
  void _showReportDialog(BuildContext context) {
    String? selectedSection;
    String? selectedClass;
    String reportType = "annual";

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("Générer Rapport PDF"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Type de Rapport"),
                  DropdownButton<String>(
                    value: reportType,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                          value: "daily", child: Text("Journalier")),
                      DropdownMenuItem(
                          value: "monthly", child: Text("Mensuel")),
                      DropdownMenuItem(
                          value: "annual", child: Text("Annuel")),
                    ],
                    onChanged: (val) =>
                        setDialogState(() => reportType = val!),
                  ),
                  const SizedBox(height: 16),
                  const Text("Filtrer par Section (optionnel)"),
                  DropdownButton<String>(
                    value: selectedSection,
                    hint: const Text("Toutes les sections"),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                          value: null,
                          child: Text("Toutes les sections")),
                      ...fraisScolaires.config.sections.map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                      ),
                    ],
                    onChanged: (val) =>
                        setDialogState(() => selectedSection = val),
                  ),
                  const SizedBox(height: 12),
                  const Text("Filtrer par Classe (optionnel)"),
                  DropdownButton<String>(
                    value: selectedClass,
                    hint: const Text("Toutes les classes"),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                          value: null,
                          child: Text("Toutes les classes")),
                      ...fraisScolaires.currentData.eleves
                          .map((e) => e.classe)
                          .toSet()
                          .map(
                            (c) =>
                            DropdownMenuItem(value: c, child: Text(c)),
                      ),
                    ],
                    onChanged: (val) =>
                        setDialogState(() => selectedClass = val),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Annuler"),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final filename =
                      "Rapport_${reportType}_${DateTime.now().toString().split(' ')[0]}";
                  await fraisScolaires.generatePdf(
                    filename: filename,
                    reportType: reportType,
                    sectionFilter: selectedSection,
                    classFilter: selectedClass,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("✅ Rapport PDF généré avec succès"),
                      ),
                    );
                  }
                },
                child: const Text("Générer PDF"),
              ),
            ],
          );
        },
      ),
    );
  }
}