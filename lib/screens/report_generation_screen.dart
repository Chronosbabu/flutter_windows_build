import 'package:flutter/material.dart';
import '../frais_scolaires.dart';

class ReportGenerationScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;

  const ReportGenerationScreen({super.key, required this.fraisScolaires});

  @override
  State<ReportGenerationScreen> createState() =>
      _ReportGenerationScreenState();
}

class _ReportGenerationScreenState extends State<ReportGenerationScreen> {
  String reportCategory = "principal";
  String? selectedSection;
  String? selectedClass;
  String reportType = "annual";
  String? selectedAutreFraisGroupeCle;
  bool includeDepenses = true;
  late final TextEditingController _cityController;
  bool _generating = false;

  FraisScolaires get fs => widget.fraisScolaires;

  @override
  void initState() {
    super.initState();
    _cityController =
        TextEditingController(text: fs.lastReportCity ?? 'Lubumbashi');
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  String _libelleGroupe(AutreFraisGroupe g) {
    final String montant = g.montantMin == g.montantMax
        ? "${formatMontant(g.montantMin)} FC"
        : "${formatMontant(g.montantMin)} à ${formatMontant(g.montantMax)} FC";
    final String fusion = g.nombreDeFraisFusionnes > 1
        ? " • ${g.nombreDeFraisFusionnes} configurations fusionnées"
        : "";
    return "${g.nom} — $montant$fusion";
  }

  String _periodeAutresFrais() {
    switch (reportType) {
      case "daily":
        return "today";
      case "monthly":
        return "month";
      default:
        return "year";
    }
  }

  @override
  Widget build(BuildContext context) {
    final signataires = fs.getSignataires();
    final List<AutreFraisGroupe> groupesAutresFrais =
    fs.getAutresFraisGroupes();

    if (selectedAutreFraisGroupeCle != null &&
        !groupesAutresFrais
            .any((g) => g.cle == selectedAutreFraisGroupeCle)) {
      selectedAutreFraisGroupeCle = null;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Générer un Rapport PDF"),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionCard(
            title: "1. Catégorie de rapport",
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: "principal",
                  label: Text("Frais Principal"),
                  icon: Icon(Icons.school),
                ),
                ButtonSegment(
                  value: "autres",
                  label: Text("Autres Frais"),
                  icon: Icon(Icons.receipt_long),
                ),
              ],
              selected: {reportCategory},
              onSelectionChanged: (newSelection) {
                setState(() {
                  reportCategory = newSelection.first;
                  selectedClass = null;
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          _sectionCard(
            title: "2. Type de rapport",
            subtitle: reportCategory == "principal"
                ? null
                : "Journalier : paiements d'aujourd'hui. Mensuel : paiements "
                "du mois en cours. Annuel : tous les paiements de l'année "
                "scolaire.",
            child: DropdownButtonFormField<String>(
              value: reportType,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem(value: "daily", child: Text("Journalier")),
                DropdownMenuItem(value: "monthly", child: Text("Mensuel")),
                DropdownMenuItem(value: "annual", child: Text("Annuel")),
              ],
              onChanged: (val) => setState(() => reportType = val!),
            ),
          ),
          const SizedBox(height: 16),
          if (reportCategory == "autres") ...[
            _sectionCard(
              title: "3. Type de frais additionnel",
              subtitle: "Choisissez un type de frais (ex: Frais de l'État) "
                  "ou tous les types confondus. Les frais portant le même "
                  "nom sont automatiquement fusionnés en un seul type "
                  "dans le rapport.",
              child: groupesAutresFrais.isEmpty
                  ? const Text(
                "Aucun frais additionnel défini. Allez dans Paramètres "
                    "> \"Autres Frais de Paiement\" pour en ajouter.",
                style: TextStyle(color: Colors.red),
              )
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String?>(
                    value: selectedAutreFraisGroupeCle,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    hint: const Text("Tous les types confondus"),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text("Tous les types confondus"),
                      ),
                      ...groupesAutresFrais.map(
                            (g) => DropdownMenuItem<String?>(
                          value: g.cle,
                          child: Text(
                            _libelleGroupe(g),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(
                            () => selectedAutreFraisGroupeCle = val),
                  ),
                  if (selectedAutreFraisGroupeCle != null) ...[
                    const SizedBox(height: 8),
                    Builder(builder: (_) {
                      final g = groupesAutresFrais.firstWhere(
                              (x) => x.cle == selectedAutreFraisGroupeCle);
                      return Text(
                        g.nombreDeFraisFusionnes > 1
                            ? "Ce rapport fusionnera "
                            "${g.nombreDeFraisFusionnes} configurations "
                            "portant le nom \"${g.nom}\" en un seul type "
                            "de frais. Les sections/classes pour "
                            "lesquelles ce frais n'a pas été défini "
                            "n'apparaîtront simplement pas."
                            : "Un seul frais porte le nom \"${g.nom}\".",
                        style: const TextStyle(
                            fontSize: 12, color: Colors.indigo),
                      );
                    }),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (reportCategory == "principal") ...[
            _sectionCard(
              title: "3. Dépenses dans le rapport",
              subtitle: includeDepenses
                  ? "La partie \"Dépenses\" (journalières, mensuelles et "
                  "annuelles, avec répartition par rubrique et par "
                  "section) sera incluse dans le PDF."
                  : "Aucune information sur les dépenses n'apparaîtra dans "
                  "le PDF. Seuls les élèves, les montants et les "
                  "signataires y figureront.",
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: includeDepenses,
                onChanged: (val) => setState(() => includeDepenses = val),
                title: const Text("Inclure la partie \"Dépenses\""),
                secondary: Icon(
                  includeDepenses
                      ? Icons.checklist_rtl
                      : Icons.checklist_rtl_outlined,
                  color: includeDepenses ? Colors.indigo : Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _sectionCard(
            title: "4. Filtres (optionnel)",
            subtitle: "Limitez le rapport à une section et/ou une classe, "
                "ou laissez sur \"Toutes\" pour couvrir toute l'école.",
            child: Column(
              children: [
                DropdownButtonFormField<String?>(
                  value: selectedSection,
                  decoration: const InputDecoration(
                    labelText: "Section",
                    border: OutlineInputBorder(),
                    contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  hint: const Text("Toutes les sections"),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text("Toutes les sections")),
                    ...fs.config.sections.map(
                          (s) => DropdownMenuItem(value: s, child: Text(s)),
                    ),
                  ],
                  onChanged: (val) => setState(() {
                    selectedSection = val;
                    selectedClass = null;
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: selectedClass,
                  decoration: const InputDecoration(
                    labelText: "Classe",
                    border: OutlineInputBorder(),
                    contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  hint: const Text("Toutes les classes"),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text("Toutes les classes")),
                    ..._classesForCurrentSectionFilter().map(
                          (c) => DropdownMenuItem(value: c, child: Text(c)),
                    ),
                  ],
                  onChanged: (val) => setState(() => selectedClass = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionCard(
            title: "5. Ville (pour la mention \"Fait à ..., le ...\")",
            subtitle: "Cette ville apparaîtra juste au-dessus des "
                "signatures, en bas du rapport (Frais Principal ou "
                "Autres Frais).",
            child: TextField(
              controller: _cityController,
              decoration: const InputDecoration(
                labelText: "Ville",
                hintText: "Ex: Lubumbashi",
                prefixIcon: Icon(Icons.location_city),
                border: OutlineInputBorder(),
                contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ),
          const SizedBox(height: 16),
          _sectionCard(
            title: "6. Signataires (optionnel)",
            subtitle: "Ces personnes apparaîtront en bas du rapport "
                "(Frais Principal ou Autres Frais), avec un espace pour signer.",
            child: Column(
              children: [
                if (signataires.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      "Aucun signataire configuré.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: signataires.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final s = signataires[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          s.nom,
                          style:
                          const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(s.fonction),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit,
                                  color: Colors.indigo),
                              onPressed: () => _showSignataireDialog(
                                idToEdit: s.id,
                                initialNom: s.nom,
                                initialFonction: s.fonction,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete,
                                  color: Colors.red),
                              onPressed: () =>
                                  _confirmDeleteSignataire(s.id, s.nom),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _showSignataireDialog(),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text("Ajouter un signataire"),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _generating ? null : _generateReport,
              icon: _generating
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.picture_as_pdf),
              label: Text(_generating ? "Génération..." : "Générer le PDF"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  List<String> _classesForCurrentSectionFilter() {
    final classes = fs.currentData.eleves
        .where(
            (e) => selectedSection == null || e.section == selectedSection)
        .map((e) => e.classe)
        .toSet()
        .toList();
    classes.sort();
    return classes;
  }

  Widget _sectionCard({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  void _showSignataireDialog({
    String? idToEdit,
    String initialNom = '',
    String initialFonction = '',
  }) {
    final nomController = TextEditingController(text: initialNom);
    final fonctionController = TextEditingController(text: initialFonction);
    final isEditing = idToEdit != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            isEditing ? "Modifier le signataire" : "Ajouter un signataire"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomController,
                decoration: const InputDecoration(
                  labelText: "Nom complet",
                  hintText: "Ex: Jean Kalala Mbuyi",
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: fonctionController,
                decoration: const InputDecoration(
                  labelText: "Fonction",
                  hintText: "Ex: Le Chef d'Établissement",
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    "Le Chef d'Établissement",
                    "Le Préfet des Études",
                    "Le Directeur",
                    "Le Caissier",
                    "Le Comptable",
                    "Le Secrétaire",
                  ].map((suggestion) {
                    return ActionChip(
                      label: Text(suggestion,
                          style: const TextStyle(fontSize: 11)),
                      onPressed: () => fonctionController.text = suggestion,
                    );
                  }).toList(),
                ),
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
              final nom = nomController.text.trim();
              final fonction = fonctionController.text.trim();
              if (nom.isEmpty || fonction.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Le nom et la fonction sont obligatoires."),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              if (isEditing) {
                await fs.updateSignataire(idToEdit, nom: nom, fonction: fonction);
              } else {
                await fs.addSignataire(nom: nom, fonction: fonction);
              }
              if (mounted) {
                Navigator.pop(ctx);
                setState(() {});
              }
            },
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSignataire(String id, String nom) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer le signataire"),
        content: Text(
            "Voulez-vous vraiment supprimer \"$nom\" de la liste des signataires ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await fs.deleteSignataire(id);
              if (mounted) {
                Navigator.pop(ctx);
                setState(() {});
              }
            },
            child:
            const Text("Supprimer", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _generateReport() async {
    setState(() => _generating = true);

    final String? city =
    _cityController.text.trim().isEmpty ? null : _cityController.text.trim();
    await fs.setLastReportCity(_cityController.text);

    final String dateJour = DateTime.now().toString().split(' ')[0];
    final Map<String, dynamic> result;
    if (reportCategory == "principal") {
      final filename = "Rapport_${reportType}_$dateJour";
      result = await fs.generatePdf(
        filename: filename,
        reportType: reportType,
        sectionFilter: selectedSection,
        classFilter: selectedClass,
        city: city,
        includeDepenses: includeDepenses,
      );
    } else {
      final filename = "Rapport_AutresFrais_${reportType}_$dateJour";
      result = await fs.generateAutresFraisPdf(
        filename: filename,
        autreFraisGroupeCle: selectedAutreFraisGroupeCle,
        sectionFilter: selectedSection,
        classFilter: selectedClass,
        city: city,
        periode: _periodeAutresFrais(),
      );
    }

    if (!mounted) return;
    setState(() => _generating = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ Rapport PDF généré : ${result['path']}"),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Échec : ${result['error']}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}