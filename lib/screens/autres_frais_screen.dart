import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../frais_scolaires.dart';
import '../models.dart';
import '../services/epson_printer_service.dart';

class AutresFraisScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const AutresFraisScreen({super.key, required this.fraisScolaires});

  @override
  State<AutresFraisScreen> createState() => _AutresFraisScreenState();
}

class _AutresFraisScreenState extends State<AutresFraisScreen> {
  final searchController = TextEditingController();
  AutreFrais? selectedFrais;
  final Set<String> selectedStudentIds = {};
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    final frais = widget.fraisScolaires.getAutresFrais();
    if (frais.isNotEmpty) selectedFrais = frais.first;
    searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<Eleve> get _eligibleFiltered {
    if (selectedFrais == null) return [];
    final query = searchController.text.toLowerCase().trim();
    final eligible =
    widget.fraisScolaires.getEligibleStudentsForAutreFrais(selectedFrais!);
    if (query.isEmpty) return eligible;
    return eligible.where((e) {
      final idMatch = e.id.toLowerCase().contains(query);
      final nameMatch =
      '${e.nom} ${e.postNom} ${e.prenom}'.toLowerCase().contains(query);
      return idMatch || nameMatch;
    }).toList();
  }

  String _scopeLabel(AutreFrais f) {
    switch (f.scope) {
      case 'section':
        return f.section ?? 'Section';
      case 'classe':
        return f.classe ?? 'Classe';
      default:
        return 'Toutes les classes';
    }
  }

  void _toggleStudent(Eleve e) {
    if (selectedFrais == null) return;
    if (widget.fraisScolaires.hasPaidAutreFrais(e, selectedFrais!)) return;
    setState(() {
      if (selectedStudentIds.contains(e.id)) {
        selectedStudentIds.remove(e.id);
      } else {
        selectedStudentIds.add(e.id);
      }
    });
  }

  Future<void> _imprimerRecu(Eleve eleve, AutreFrais frais) async {
    final prefs = await SharedPreferences.getInstance();
    final printerName = prefs.getString('printer_name') ?? '';
    if (printerName.isEmpty) return;
    await EscPosPrinterService.printAutreFraisReceipt(
      printerName: printerName,
      schoolName: widget.fraisScolaires.config.schoolName,
      titreFrais: frais.nom,
      studentName: '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      classe: eleve.classe,
      section: eleve.section,
      montant: frais.montant,
    );
  }

  Future<void> _payerUnSeul(Eleve eleve) async {
    if (selectedFrais == null) return;
    if (widget.fraisScolaires.hasPaidAutreFrais(eleve, selectedFrais!)) return;
    setState(() => _processing = true);
    final frais = selectedFrais!;
    await widget.fraisScolaires.payAutreFrais(frais: frais, eleve: eleve);
    await _imprimerRecu(eleve, frais);
    if (mounted) {
      setState(() {
        selectedStudentIds.remove(eleve.id);
        _processing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                "✅ ${frais.nom} enregistré pour ${eleve.nom} ${eleve.prenom}")),
      );
    }
  }

  Future<void> _payerSelection() async {
    if (selectedFrais == null || selectedStudentIds.isEmpty) return;
    setState(() => _processing = true);

    final frais = selectedFrais!;
    final students = widget.fraisScolaires.currentData.eleves
        .where((e) => selectedStudentIds.contains(e.id))
        .toList();

    int success = 0;
    for (final eleve in students) {
      if (widget.fraisScolaires.hasPaidAutreFrais(eleve, frais)) continue;
      await widget.fraisScolaires.payAutreFrais(frais: frais, eleve: eleve);
      success++;
      await _imprimerRecu(eleve, frais);
    }

    if (mounted) {
      setState(() {
        selectedStudentIds.clear();
        _processing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
            Text("✅ Paiement de \"${frais.nom}\" enregistré pour $success élève(s)")),
      );
    }
  }

  void _confirmPaiementUnique(Eleve eleve) {
    if (selectedFrais == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(selectedFrais!.nom),
        content: Text(
          "Confirmer le paiement de "
              "${selectedFrais!.montant.toStringAsFixed(0)} FC pour "
              "${eleve.nom} ${eleve.prenom} (${eleve.classe}) ?",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _payerUnSeul(eleve);
            },
            child: const Text("Confirmer"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fraisList = widget.fraisScolaires.getAutresFrais();

    return Scaffold(
      appBar: AppBar(title: const Text("Autres Frais de Paiement")),
      body: fraisList.isEmpty
          ? _buildEmptyState()
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                DropdownButtonFormField<AutreFrais>(
                  value: selectedFrais,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: "Type de frais",
                    border: OutlineInputBorder(),
                  ),
                  items: fraisList
                      .map(
                        (f) => DropdownMenuItem(
                      value: f,
                      child: Text(
                          "${f.nom} — ${f.montant.toStringAsFixed(0)} FC (${_scopeLabel(f)})"),
                    ),
                  )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedFrais = value;
                      selectedStudentIds.clear();
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    labelText: "Rechercher par ID ou Nom",
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ],
            ),
          ),
          if (selectedFrais != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "${_eligibleFiltered.length} élève(s) concerné(s) — cochez "
                      "ceux qui payent, ou utilisez le bouton paiement direct.",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ),
          if (selectedFrais != null)
            Expanded(
              child: ListView.builder(
                itemCount: _eligibleFiltered.length,
                itemBuilder: (context, index) {
                  final eleve = _eligibleFiltered[index];
                  final dejaPaye = widget.fraisScolaires
                      .hasPaidAutreFrais(eleve, selectedFrais!);
                  final isSelected = selectedStudentIds.contains(eleve.id);
                  return Card(
                    margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    color: dejaPaye ? Colors.green.withAlpha(20) : null,
                    child: ListTile(
                      leading: dejaPaye
                          ? const Icon(Icons.check_circle,
                          color: Colors.green)
                          : Checkbox(
                        value: isSelected,
                        onChanged: (_) => _toggleStudent(eleve),
                      ),
                      title: Text(
                          '${eleve.nom} ${eleve.postNom} ${eleve.prenom}'),
                      subtitle: Text(
                        'ID: ${eleve.id} | Classe: ${eleve.classe} (${eleve.section})',
                      ),
                      trailing: dejaPaye
                          ? const Text(
                        "Payé",
                        style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold),
                      )
                          : IconButton(
                        icon: const Icon(Icons.payment,
                            color: Colors.indigo),
                        onPressed: _processing
                            ? null
                            : () => _confirmPaiementUnique(eleve),
                      ),
                      onTap: dejaPaye ? null : () => _toggleStudent(eleve),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
      bottomNavigationBar:
      (selectedFrais != null && selectedStudentIds.isNotEmpty)
          ? SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            icon: _processing
                ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.payment),
            label: Text(_processing
                ? "Traitement..."
                : "Payer pour ${selectedStudentIds.length} élève(s)"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
            ),
            onPressed: _processing ? null : _payerSelection,
          ),
        ),
      )
          : null,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.receipt_long, size: 60, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              "Aucun frais additionnel défini pour le moment.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              "Allez dans Paramètres > \"Autres Frais de Paiement\" pour en "
                  "ajouter (ex: Frais de l'État, Frais d'Aide...).",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}