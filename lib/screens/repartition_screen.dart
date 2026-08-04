import 'package:flutter/material.dart';
import '../frais_scolaires.dart';

class RepartitionScreen extends StatelessWidget {
  final FraisScolaires fraisScolaires;
  const RepartitionScreen({super.key, required this.fraisScolaires});

  @override
  Widget build(BuildContext context) {
    final totalGeneral = fraisScolaires.getYearTotalCollected();
    final totalsByClass = fraisScolaires.getTotalByClass();

    return Scaffold(
      appBar: AppBar(title: const Text("Répartition par Administration")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Total Collecte Global", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text("${totalGeneral.toStringAsFixed(0)} FC", style: const TextStyle(fontSize: 24, color: Colors.green)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text("Montant par Classe", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ...totalsByClass.entries.map((entry) => ListTile(
              title: Text(entry.key),
              trailing: Text("${entry.value.toStringAsFixed(0)} FC"),
            )),
            const Divider(),
            const Text("Répartition aux Administrations", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ...fraisScolaires.config.administrations.map((admin) {
              double montant = totalGeneral * (admin.pourcentage / 100);
              return ListTile(
                title: Text(admin.nom),
                subtitle: Text("${admin.pourcentage}%"),
                trailing: Text("${montant.toStringAsFixed(0)} FC"),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}