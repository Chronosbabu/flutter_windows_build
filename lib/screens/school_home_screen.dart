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
import 'liste_ordre_screen.dart';
// ⚡ NOUVEAU — Module Discipline
import 'discipline_registre_screen.dart';
// ⚡ NOUVEAU — Autres Frais de Paiement (éphémères)
import 'autres_frais_screen.dart';
// ⚡ NOUVEAU — Écran dédié à la génération de rapport PDF (remplace
// l'ancienne boîte de dialogue) : filtres + gestion des signataires.
import 'report_generation_screen.dart';

class SchoolHomeScreen extends StatefulWidget {
  const SchoolHomeScreen({super.key});

  @override
  State<SchoolHomeScreen> createState() => _SchoolHomeScreenState();
}

class _SchoolHomeScreenState extends State<SchoolHomeScreen> {
  late FraisScolaires fraisScolaires;

  // ⚡ évite de ré-écraser schoolCode à chaque frame/build tant que le
  // chargement initial n'est pas terminé.
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    fraisScolaires = FraisScolaires();
    _loadData();
  }

  Future<void> _loadData() async {
    final appState = Provider.of<AppState>(context, listen: false);

    await fraisScolaires.loadData();

    final localCode = fraisScolaires.schoolCode;
    final stateCode = appState.schoolCode;

    if (stateCode != null && stateCode.isNotEmpty) {
      if (localCode != stateCode) {
        fraisScolaires.schoolCode = stateCode;
        await fraisScolaires.saveData();
      }
    } else if (localCode != null && localCode.isNotEmpty) {
      await appState.setSchoolCode(localCode);
    }

    _initialLoadDone = true;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

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
                // ⚡ NOUVEAU — Autres Frais de Paiement (éphémères, ex:
                // Frais de l'État, Frais d'Aide...).
                _buildCard(
                  Icons.request_page,
                  "Autres Frais",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AutresFraisScreen(
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
                // ⚡ CORRIGÉ — ouvre désormais une vraie page dédiée
                // (ReportGenerationScreen) au lieu d'une boîte de
                // dialogue, avec gestion des signataires du rapport.
                _buildCard(
                  Icons.picture_as_pdf,
                  "Rapport PDF",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReportGenerationScreen(
                          fraisScolaires: fraisScolaires),
                    ),
                  ),
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
                _buildCard(
                  Icons.fact_check,
                  "Liste En Ordre",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ListeOrdreScreen(fraisScolaires: fraisScolaires),
                    ),
                  ),
                ),
                // ⚡ NOUVEAU — Module Discipline : registre d'absences,
                // convocations individuelles et communiqués aux parents.
                _buildCard(
                  Icons.rule_folder,
                  "Discipline",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DisciplineRegistreScreen(
                          fraisScolaires: fraisScolaires),
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
}