import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../frais_scolaires.dart';
import '../app_state.dart';

import 'enregistrer_eleve_screen.dart';
import 'paiement_eleve_screen.dart';
import 'repartition_screen.dart';
import 'settings_screen.dart';

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
    await fraisScolaires.loadData();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
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
                    Text('Total Collecte : ${fraisScolaires.getYearTotalCollected().toStringAsFixed(0)} FC'),
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

                _buildCard(Icons.picture_as_pdf, "Rapport PDF",
                        () => _showReportDialog(context)),

                _buildCard(Icons.share, "Répartition",
                        () => Navigator.push(context, MaterialPageRoute(builder: (_) => RepartitionScreen(fraisScolaires: fraisScolaires)))),
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
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  // ==================== NOUVELLE BOÎTE DE DIALOGUE POUR CHOISIR LE TYPE DE RAPPORT ====================
  void _showReportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Type de Rapport PDF"),
        content: const Text("Choisissez le type de rapport à générer :"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _generateSpecificReport("daily");
            },
            child: const Text("Journalier"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _generateSpecificReport("monthly");
            },
            child: const Text("Mensuel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _generateSpecificReport("annual");
            },
            child: const Text("Annuel"),
          ),
        ],
      ),
    );
  }

  Future<void> _generateSpecificReport(String type) async {
    String reportName = "";
    if (type == "daily") reportName = "Journalier";
    else if (type == "monthly") reportName = "Mensuel";
    else reportName = "Annuel";

    final filename = "Rapport_${reportName}_${DateTime.now().toString().split(' ')[0]}";

    try {
      await fraisScolaires.generatePdf(filename, type);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Rapport $reportName généré avec succès")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Erreur lors de la génération : $e")),
        );
      }
    }
  }
}
