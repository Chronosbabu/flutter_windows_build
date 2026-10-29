import 'package:flutter/material.dart';
import '../frais_scolaires.dart';
import '../models.dart';
import '../services/cahier_paiement_service.dart';

class ListeOrdreScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;

  const ListeOrdreScreen({super.key, required this.fraisScolaires});

  @override
  State<ListeOrdreScreen> createState() => _ListeOrdreScreenState();
}

class _ListeOrdreScreenState extends State<ListeOrdreScreen> {
  String? selectedSection;
  String? selectedClasse;
  String selectedMois = '';
  // true = "Ont déjà payé" (en ordre) | false = "N'ont pas encore payé"
  bool enOrdre = true;
  List<Eleve> resultats = [];
  bool listeGeneree = false;

  // ⚡ NOUVEAU — indique qu'un cahier de paiement est en cours de génération
  bool _generationCahier = false;

  @override
  void initState() {
    super.initState();
    if (widget.fraisScolaires.months.isNotEmpty) {
      selectedMois = widget.fraisScolaires.months.first;
    }
  }

  List<String> get _classesDisponibles {
    if (selectedSection != null) {
      return widget.fraisScolaires
          .getAllDisplayClassesForSection(selectedSection!);
    }
    return widget.fraisScolaires.getAllDisplayClasses();
  }

  void _genererListe() {
    if (selectedMois.isEmpty) return;
    setState(() {
      // ⚡ getStudentsByOrderStatus utilise déjà en interne
      // isStudentEnOrdrePourMois -> getRequiredForMonthForEleve, donc un
      // élève avec une exception de paiement personnalisée est
      // automatiquement classé "en ordre" / "pas en ordre" en fonction de
      // SON propre montant requis, et non celui de sa section/classe.
      resultats = widget.fraisScolaires.getStudentsByOrderStatus(
        mois: selectedMois,
        enOrdre: enOrdre,
        sectionFilter: selectedSection,
        classFilter: selectedClasse,
      );
      listeGeneree = true;
    });
  }

  Future<void> _genererPdf() async {
    if (!listeGeneree) return;

    final controller = TextEditingController(
      text: enOrdre
          ? "Liste_En_Ordre_$selectedMois"
          : "Liste_Pas_En_Ordre_$selectedMois",
    );

    final filename = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Titre du fichier PDF"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "Nom du fichier",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text("Générer"),
          ),
        ],
      ),
    );

    if (filename == null || filename.isEmpty) return;

    // ⚡ generateOrderStatusPdf utilise déjà en interne
    // getRequiredForMonthForEleve pour la colonne "Payé / Requis", donc
    // le PDF reflète lui aussi correctement les montants personnalisés.
    await widget.fraisScolaires.generateOrderStatusPdf(
      filename: filename,
      mois: selectedMois,
      enOrdre: enOrdre,
      sectionFilter: selectedSection,
      classFilter: selectedClasse,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Fichier PDF généré avec succès"),
        ),
      );
    }
  }

  // ==========================================================================
  // ⚡ NOUVEAU — CAHIER DE PAIEMENT (PDF)
  // ==========================================================================
  // Génère un cahier de paiement pour la section / classe actuellement
  // choisies dans les filtres ci-dessus (toutes si rien n'est choisi).
  // Le mois et le statut "Ont déjà payé / Pas encore payé" ne sont PAS
  // utilisés : le cahier montre tous les mois, de Septembre à Juin.
  // Fonction en lecture seule : aucune donnée de l'école n'est modifiée.
  Future<void> _genererCahier() async {
    if (_generationCahier) return;

    final String sectionTxt = selectedSection ?? "Toutes les sections";
    final String classeTxt = selectedClasse ?? "Toutes les classes";
    final String nomParDefaut =
    "Cahier_Paiement_${selectedSection ?? 'Toutes_Sections'}_${selectedClasse ?? 'Toutes_Classes'}"
        .replaceAll(' ', '_');

    final controller = TextEditingController(text: nomParDefaut);

    final filename = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Cahier de paiement (PDF)"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Section : $sectionTxt\nClasse : $classeTxt",
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              "Une page (ou plus) par classe, avec tous les élèves et les "
                  "mois de Septembre à Juin : montant payé, mois soldé ou "
                  "reste à payer.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: "Nom du fichier",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text("Générer"),
          ),
        ],
      ),
    );

    if (filename == null || filename.isEmpty) return;

    setState(() => _generationCahier = true);

    final resultat = await genererCahierPaiementPdf(
      fraisScolaires: widget.fraisScolaires,
      filename: filename,
      sectionFilter: selectedSection,
      classFilter: selectedClasse,
    );

    if (!mounted) return;
    setState(() => _generationCahier = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          resultat.succes
              ? "✅ Cahier généré : ${resultat.nbEleves} élève(s), "
              "${resultat.nbClasses} classe(s).\nFichier : ${resultat.chemin}"
              : "❌ ${resultat.erreur ?? 'Erreur inconnue'}",
        ),
        backgroundColor: resultat.succes ? Colors.green : Colors.red,
        duration: const Duration(seconds: 7),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sectionLabel = selectedSection ?? "Toutes les sections";
    final classeLabel = selectedClasse ?? "Toutes les classes";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Liste En Ordre / Pas En Ordre"),
        centerTitle: true,
        actions: [
          if (listeGeneree && resultats.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: "Générer le PDF",
              onPressed: _genererPdf,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ==================== FILTRES ====================
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text("Toutes Sections"),
                    value: selectedSection,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text("Toutes Sections"),
                      ),
                      ...widget.fraisScolaires.config.sections
                          .map((s) => DropdownMenuItem(value: s, child: Text(s))),
                    ],
                    onChanged: (val) {
                      setState(() {
                        selectedSection = val;
                        selectedClasse = null;
                        listeGeneree = false;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text("Toutes Classes"),
                    value: selectedClasse,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text("Toutes Classes"),
                      ),
                      ..._classesDisponibles
                          .map((c) => DropdownMenuItem(value: c, child: Text(c))),
                    ],
                    onChanged: (val) {
                      setState(() {
                        selectedClasse = val;
                        listeGeneree = false;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text("Mois"),
                    value: selectedMois.isEmpty ? null : selectedMois,
                    items: widget.fraisScolaires.months
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() {
                        selectedMois = val;
                        listeGeneree = false;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Statut de paiement
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text("Ont déjà payé"),
                    selected: enOrdre == true,
                    onSelected: (_) {
                      setState(() {
                        enOrdre = true;
                        listeGeneree = false;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text("Pas encore payé"),
                    selected: enOrdre == false,
                    onSelected: (_) {
                      setState(() {
                        enOrdre = false;
                        listeGeneree = false;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.filter_alt),
                label: const Text("Générer la Liste"),
                onPressed: _genererListe,
              ),
            ),
            const SizedBox(height: 8),

            // ==================== ⚡ NOUVEAU — CAHIER DE PAIEMENT ====================
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: _generationCahier
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.menu_book),
                label: Text(_generationCahier
                    ? "Génération du cahier..."
                    : "Cahier de paiement (PDF)"),
                onPressed: _generationCahier ? null : _genererCahier,
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                "Le cahier utilise la section et la classe choisies ci-dessus "
                    "(toutes si rien n'est choisi) et montre tous les mois.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),

            // ==================== RÉSUMÉ ====================
            if (listeGeneree)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: enOrdre
                      ? Colors.green.withOpacity(0.08)
                      : Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: enOrdre
                        ? Colors.green.withOpacity(0.35)
                        : Colors.red.withOpacity(0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      enOrdre
                          ? "Élèves qui ont déjà payé $selectedMois"
                          : "Élèves qui n'ont pas encore payé $selectedMois",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Section : $sectionLabel  |  Classe : $classeLabel",
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Total : ${resultats.length} élève(s)",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

            // ==================== LISTE ====================
            Expanded(
              child: !listeGeneree
                  ? const Center(
                child: Text(
                  "Sélectionnez les filtres puis appuyez sur « Générer la Liste »",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
                  : resultats.isEmpty
                  ? const Center(
                child: Text(
                  "Aucun élève ne correspond à ces critères.",
                  style: TextStyle(color: Colors.grey),
                ),
              )
                  : ListView.builder(
                itemCount: resultats.length,
                itemBuilder: (context, index) {
                  final e = resultats[index];
                  final paye = e.paid[selectedMois] ?? 0;
                  // ⚡ CORRIGÉ — utilise désormais
                  // getRequiredForMonthForEleve pour que le montant
                  // affiché soit bien celui de CET élève (montant
                  // personnalisé si exception, sinon montant normal
                  // de sa section/classe).
                  final requis = widget.fraisScolaires
                      .getRequiredForMonthForEleve(e, selectedMois);

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                        enOrdre ? Colors.green : Colors.red,
                        child: Text(
                          "${index + 1}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              "${e.nom} ${e.postNom} ${e.prenom}",
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          // ⚡ NOUVEAU — petit badge si l'élève a une
                          // exception de paiement personnalisée, pour
                          // que ce soit visible directement dans la liste.
                          if (e.montantMensuelPersonnalise != null)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.star,
                                  size: 16, color: Colors.indigo),
                            ),
                        ],
                      ),
                      subtitle: Text("${e.section} - ${e.classe}"),
                      trailing: Text(
                        "${paye.toStringAsFixed(0)} / ${requis.toStringAsFixed(0)} FC",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: enOrdre
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Bouton PDF en bas si liste générée
            if (listeGeneree && resultats.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text("Générer le PDF"),
                  onPressed: _genererPdf,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}