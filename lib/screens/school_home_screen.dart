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
                context, MaterialPageRoute(builder: (_) => SettingsScreen(fraisScolaires: fraisScolaires))),
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

  void _showReportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Générer Rapport PDF"),
        content: const Text("Le rapport sera généré avec les montants par section et la répartition."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx); // Ferme la boîte de dialogue

              try {
                final filename = "Rapport_${DateTime.now().toString().split(' ')[0]}";
                await fraisScolaires.generatePdf(filename);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("✅ PDF généré et ouvert avec succès !"),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("❌ Erreur lors de la génération du PDF: $e"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text("Générer le PDF"),
          ),
        ],
      ),
    );
  }
}
