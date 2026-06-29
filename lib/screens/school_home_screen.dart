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

class SchoolHomeScreen extends StatefulWidget {
  const SchoolHomeScreen({super.key});

  @override
  State<SchoolHomeScreen> createState() => _SchoolHomeScreenState();
}

class _SchoolHomeScreenState extends State<SchoolHomeScreen> {
  late FraisScolaires fraisScolaires;

  @override
  void initState() {
    super.initState();
    fraisScolaires = FraisScolaires();
    _loadData();
  }

  Future<void> _loadData() async {
    // IMPORTANT : on renseigne le schoolCode AVANT loadData(), pour que
    // _assignMissingIds() puisse contacter le serveur si besoin.
    final appState = Provider.of<AppState>(context, listen: false);
    fraisScolaires.schoolCode = appState.schoolCode;

    await fraisScolaires.loadData();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    // Garde le schoolCode synchronisé si l'admin le change depuis les Paramètres.
    fraisScolaires.schoolCode = appState.schoolCode;

    return Scaffold(
      appBar: AppBar(
        title: Text("${appState.schoolName} - ${fraisScolaires.currentYear}"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SettingsScreen(fraisScolaires: fraisScolaires)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text('Année : ${fraisScolaires.currentYear}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text('Élèves : ${fraisScolaires.currentData.eleves.length}'),
                    Text('Total Collecté : ${fraisScolaires.getYearTotalCollected().toStringAsFixed(0)} FC'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.1,
              children: [
                _buildCard(Icons.person_add, "Ajouter Élève",
                        () => Navigator.push(context, MaterialPageRoute(builder: (_) => EnregistrerEleveScreen(fraisScolaires: fraisScolaires)))),

                _buildCard(Icons.payment, "Paiements",
                        () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaiementEleveScreen(fraisScolaires: fraisScolaires)))),

                _buildCard(Icons.list_alt, "Registre des Élèves",
                        () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentListScreen(fraisScolaires: fraisScolaires)))),

                _buildCard(Icons.picture_as_pdf, "Rapport PDF",
                        () => _showReportDialog(context)),

                _buildCard(Icons.share, "Répartition",
                        () => Navigator.push(context, MaterialPageRoute(builder: (_) => RepartitionScreen(fraisScolaires: fraisScolaires)))),

                _buildCard(Icons.admin_panel_settings, "Admin Dashboard",
                        () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminDashboardScreen(fraisScolaires: fraisScolaires)))),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 50, color: Colors.indigo),
            const SizedBox(height: 12),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                      DropdownMenuItem(value: "daily", child: Text("Journalier")),
                      DropdownMenuItem(value: "monthly", child: Text("Mensuel")),
                      DropdownMenuItem(value: "annual", child: Text("Annuel")),
                    ],
                    onChanged: (val) => setDialogState(() => reportType = val!),
                  ),
                  const SizedBox(height: 16),

                  const Text("Filtrer par Section (optionnel)"),
                  DropdownButton<String>(
                    value: selectedSection,
                    hint: const Text("Toutes les sections"),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(value: null, child: Text("Toutes les sections")),
                      ...fraisScolaires.config.sections.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                    ],
                    onChanged: (val) => setDialogState(() => selectedSection = val),
                  ),
                  const SizedBox(height: 12),

                  const Text("Filtrer par Classe (optionnel)"),
                  DropdownButton<String>(
                    value: selectedClass,
                    hint: const Text("Toutes les classes"),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(value: null, child: Text("Toutes les classes")),
                      ...fraisScolaires.currentData.eleves
                          .map((e) => e.classe)
                          .toSet()
                          .map((c) => DropdownMenuItem(value: c, child: Text(c))),
                    ],
                    onChanged: (val) => setDialogState(() => selectedClass = val),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final filename = "Rapport_${reportType}_${DateTime.now().toString().split(' ')[0]}";

                  await fraisScolaires.generatePdf(
                    filename: filename,
                    reportType: reportType,
                    sectionFilter: selectedSection,
                    classFilter: selectedClass,
                  );

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("✅ Rapport PDF généré avec succès")),
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