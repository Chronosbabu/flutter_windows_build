import 'package:flutter/material.dart';
import '../frais_scolaires.dart';
import '../models.dart';

class PaiementEleveScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const PaiementEleveScreen({super.key, required this.fraisScolaires});

  @override
  State<PaiementEleveScreen> createState() => _PaiementEleveScreenState();
}

class _PaiementEleveScreenState extends State<PaiementEleveScreen> {
  final searchController = TextEditingController();
  String? selectedClassFilter;
  String? selectedSectionFilter;
  List<Eleve> filtered = [];

  @override
  void initState() {
    super.initState();
    selectedClassFilter = widget.fraisScolaires.lastSelectedClassFilter;
    selectedSectionFilter = widget.fraisScolaires.lastSelectedSectionFilter;
    _filterEleves();
    searchController.addListener(_filterEleves);
  }

  void _filterEleves() {
    final query = searchController.text.toLowerCase().trim();

    setState(() {
      filtered = widget.fraisScolaires.currentData.eleves.where((e) {
        final idMatch = e.id.toLowerCase().contains(query);
        final nameMatch = '${e.nom} ${e.postNom} ${e.prenom}'.toLowerCase().contains(query);
        final classMatch = selectedClassFilter == null || e.classe == selectedClassFilter;
        final sectionMatch = selectedSectionFilter == null || e.section == selectedSectionFilter;

        return (idMatch || nameMatch) && classMatch && sectionMatch;
      }).toList();
    });
  }

  @override
  void dispose() {
    widget.fraisScolaires.lastSelectedClassFilter = selectedClassFilter;
    widget.fraisScolaires.lastSelectedSectionFilter = selectedSectionFilter;
    widget.fraisScolaires.saveData();
    searchController.dispose();
    super.dispose();
  }

  void _showEditStudentDialog(Eleve eleve) {
    final nomController = TextEditingController(text: eleve.nom);
    final postNomController = TextEditingController(text: eleve.postNom);
    final prenomController = TextEditingController(text: eleve.prenom);
    String? selectedClasseEdit = eleve.classe;
    String? selectedSectionEdit = eleve.section;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Modifier l'élève"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("ID: ${eleve.id}", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              TextField(controller: nomController, decoration: const InputDecoration(labelText: "Nom")),
              TextField(controller: postNomController, decoration: const InputDecoration(labelText: "Post-nom")),
              TextField(controller: prenomController, decoration: const InputDecoration(labelText: "Prénom")),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                value: selectedClasseEdit,
                decoration: const InputDecoration(labelText: "Classe"),
                items: ['7ème', '8ème', '1ère', '2ème', '3ème', '4ème']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (value) => selectedClasseEdit = value,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selectedSectionEdit,
                decoration: const InputDecoration(labelText: "Section"),
                items: widget.fraisScolaires.config.sections
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (value) => selectedSectionEdit = value,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              if (nomController.text.isNotEmpty && postNomController.text.isNotEmpty &&
                  selectedClasseEdit != null && selectedSectionEdit != null) {
                eleve.nom = nomController.text.trim();
                eleve.postNom = postNomController.text.trim();
                eleve.prenom = prenomController.text.trim();
                eleve.classe = selectedClasseEdit!;
                eleve.section = selectedSectionEdit!;
                await widget.fraisScolaires.saveData();
                _filterEleves();
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Élève modifié avec succès")));
                }
              }
            },
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Paiements des Élèves")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    labelText: "Rechercher par ID ou Nom",
                    prefixIcon: Icon(Icons.search),
                    hintText: "Ex: BB26B10 ou BARAKA",
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        hint: const Text("Toutes les classes"),
                        value: selectedClassFilter,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(value: null, child: Text("Toutes les classes")),
                          ...['7ème', '8ème', '1ère', '2ème', '3ème', '4ème']
                              .map((c) => DropdownMenuItem(value: c, child: Text(c))),
                        ],
                        onChanged: (value) {
                          setState(() {
                            selectedClassFilter = value;
                            _filterEleves();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButton<String>(
                        hint: const Text("Toutes les sections"),
                        value: selectedSectionFilter,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(value: null, child: Text("Toutes les sections")),
                          ...widget.fraisScolaires.config.sections
                              .map((s) => DropdownMenuItem(value: s, child: Text(s))),
                        ],
                        onChanged: (value) {
                          setState(() {
                            selectedSectionFilter = value;
                            _filterEleves();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final eleve = filtered[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(eleve.id.substring(0, 2)),
                    ),
                    title: Text('${eleve.nom} ${eleve.postNom} ${eleve.prenom}'),
                    subtitle: Text(
                      'ID: ${eleve.id}\n'
                          'Classe: ${eleve.classe} | Section: ${eleve.section}\n'
                          'Total payé: ${widget.fraisScolaires.getStudentTotalPaid(eleve)} FC',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showEditStudentDialog(eleve),
                        ),
                        const Icon(Icons.arrow_forward_ios),
                      ],
                    ),
                    onTap: () => _showMonthsDialog(context, eleve),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showMonthsDialog(BuildContext context, Eleve eleve) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${eleve.nom} ${eleve.prenom} - ${eleve.classe} (${eleve.section})'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: widget.fraisScolaires.months.length,
            itemBuilder: (context, i) {
              final mois = widget.fraisScolaires.months[i];
              final required = widget.fraisScolaires.getRequiredForMonth(mois, eleve.section);
              final paid = eleve.paid[mois] ?? 0;
              final isFullyPaid = paid >= required;
              return ListTile(
                title: Text(mois),
                subtitle: Text('Requis: $required FC | Payé: $paid FC'),
                trailing: isFullyPaid
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.warning, color: Colors.orange),
                onTap: isFullyPaid ? null : () {
                  Navigator.pop(ctx);
                  _showPaymentDialog(context, eleve, mois);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Fermer")),
        ],
      ),
    );
  }

  void _showPaymentDialog(BuildContext context, Eleve eleve, String mois) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Paiement - $mois (${eleve.section})"),
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
                widget.fraisScolaires.handlePayment(eleve, mois, amount);
                await widget.fraisScolaires.saveData();
                Navigator.pop(ctx);
                if (mounted) {
                  _filterEleves(); // Rafraîchissement immédiat
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Paiement enregistré avec succès")),
                  );
                }
              }
            },
            child: const Text("Confirmer"),
          ),
        ],
      ),
    );
  }
}
