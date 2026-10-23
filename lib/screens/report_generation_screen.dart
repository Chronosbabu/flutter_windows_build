import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  // ⚡ NOUVEAU — mois choisi pour le rapport mensuel (null = mois en cours)
  String? selectedMois;
  bool includeDepenses = true;
  late final TextEditingController _cityController;
  bool _generating = false;

  // ⚡ NOUVEAU — accès masqué aux montants personnalisés du rapport :
  // 3 appuis rapides sur le titre de la page.
  int _tapsTitre = 0;
  DateTime? _dernierTapTitre;
  bool _dialogRapportPersonnaliseOuvert = false;

  FraisScolaires get fs => widget.fraisScolaires;

  @override
  void initState() {
    super.initState();
    _cityController =
        TextEditingController(text: fs.lastReportCity ?? 'Lubumbashi');
    // Chargement silencieux du réglage (aucun effet visible).
    rapportPersonnalise.charger();
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // ⚡ NOUVEAU — ouverture masquée de la fonctionnalité
  // --------------------------------------------------------------------------
  void _onTitreTap() {
    final now = DateTime.now();
    if (_dernierTapTitre == null ||
        now.difference(_dernierTapTitre!) > const Duration(seconds: 2)) {
      _tapsTitre = 0;
    }
    _dernierTapTitre = now;
    _tapsTitre++;
    if (_tapsTitre >= 3) {
      _tapsTitre = 0;
      _dernierTapTitre = null;
      _ouvrirRapportPersonnalise();
    }
  }

  Future<void> _ouvrirRapportPersonnalise() async {
    if (_dialogRapportPersonnaliseOuvert) return;
    _dialogRapportPersonnaliseOuvert = true;
    try {
      await rapportPersonnalise.charger();
      if (!mounted) return;

      final bool? acces = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _MotDePasseRapportDialog(),
      );
      if (acces != true || !mounted) return;

      final bool? enregistre = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RapportPersonnaliseDialog(fs: fs),
      );
      if (!mounted) return;

      if (enregistre == true) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              rapportPersonnalise.enVigueur
                  ? "✅ Montants du rapport enregistrés et activés."
                  : "✅ Enregistré. Les rapports utilisent les montants réels.",
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } finally {
      _dialogRapportPersonnaliseOuvert = false;
    }
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
        // ⚡ NOUVEAU — le titre est cliquable (3 appuis) sans rien changer
        // à son apparence.
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTitreTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text("Générer un Rapport PDF"),
          ),
        ),
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
                ? "Pour un rapport Mensuel, vous pouvez choisir le mois "
                "en cours ou un mois passé (Septembre, Octobre, ...)."
                : "Journalier : paiements d'aujourd'hui. Mensuel : paiements "
                "du mois choisi (mois en cours ou mois passé). Annuel : tous "
                "les paiements de l'année scolaire.",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: reportType,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: "daily", child: Text("Journalier")),
                    DropdownMenuItem(
                        value: "monthly", child: Text("Mensuel")),
                    DropdownMenuItem(value: "annual", child: Text("Annuel")),
                  ],
                  onChanged: (val) => setState(() => reportType = val!),
                ),
                if (reportType == "monthly") ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    value: selectedMois,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: "Mois du rapport",
                      prefixIcon: Icon(Icons.calendar_month),
                      border: OutlineInputBorder(),
                      contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          fs.currentSchoolMonthName != null
                              ? "Mois en cours (${fs.currentSchoolMonthName})"
                              : "Mois en cours",
                        ),
                      ),
                      ...fs.months.map(
                            (m) => DropdownMenuItem<String?>(
                          value: m,
                          child: Text(m),
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(() => selectedMois = val),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    selectedMois == null
                        ? "Le rapport portera sur le mois en cours."
                        : "Le rapport portera sur le mois de $selectedMois "
                        "(année scolaire ${fs.currentYear}) : élèves, montants, "
                        "répartition par administration et dépenses de ce mois.",
                    style:
                    const TextStyle(fontSize: 12, color: Colors.indigo),
                  ),
                ],
              ],
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
                  ? "La partie \"Dépenses\" (avec répartition par rubrique et "
                  "par section) sera incluse dans le PDF. Pour un rapport "
                  "mensuel d'un mois choisi, seules les dépenses de ce mois "
                  "sont affichées."
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

    // ⚡ NOUVEAU — le mois choisi ne s'applique qu'au rapport mensuel.
    final String? moisChoisi =
    reportType == "monthly" ? selectedMois : null;
    final String suffixeMois = moisChoisi != null ? "_$moisChoisi" : "";

    final Map<String, dynamic> result;
    if (reportCategory == "principal") {
      final filename = "Rapport_$reportType$suffixeMois" "_$dateJour";
      result = await fs.generatePdf(
        filename: filename,
        reportType: reportType,
        sectionFilter: selectedSection,
        classFilter: selectedClass,
        city: city,
        includeDepenses: includeDepenses,
        mois: moisChoisi,
      );
    } else {
      final filename =
          "Rapport_AutresFrais_$reportType$suffixeMois" "_$dateJour";
      result = await fs.generateAutresFraisPdf(
        filename: filename,
        autreFraisGroupeCle: selectedAutreFraisGroupeCle,
        sectionFilter: selectedSection,
        classFilter: selectedClass,
        city: city,
        periode: _periodeAutresFrais(),
        mois: moisChoisi,
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

// ============================================================================
// ⚡ NOUVEAU — BOÎTE DE DIALOGUE « MOT DE PASSE »
// ============================================================================
// Retourne true si le mot de passe est correct. Après 3 erreurs, l'accès est
// verrouillé pendant 60 secondes (géré par rapportPersonnalise).
// ============================================================================
class _MotDePasseRapportDialog extends StatefulWidget {
  const _MotDePasseRapportDialog();

  @override
  State<_MotDePasseRapportDialog> createState() =>
      _MotDePasseRapportDialogState();
}

class _MotDePasseRapportDialogState extends State<_MotDePasseRapportDialog> {
  final TextEditingController _ctrl = TextEditingController();
  bool _masque = true;
  String? _erreur;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _valider() {
    final String? erreur = rapportPersonnalise.verifierMotDePasse(_ctrl.text);
    if (erreur == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _erreur = erreur;
      _ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_outline, color: Colors.indigo),
          SizedBox(width: 8),
          Text("Accès protégé"),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Entrez le mot de passe pour continuer."),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            obscureText: _masque,
            enableSuggestions: false,
            autocorrect: false,
            onSubmitted: (_) => _valider(),
            decoration: InputDecoration(
              labelText: "Mot de passe",
              border: const OutlineInputBorder(),
              errorText: _erreur,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                icon: Icon(
                    _masque ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _masque = !_masque),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("Annuler"),
        ),
        ElevatedButton(
          onPressed: _valider,
          child: const Text("Valider"),
        ),
      ],
    );
  }
}

// ============================================================================
// ⚡ NOUVEAU — BOÎTE DE DIALOGUE « MONTANTS PERSONNALISÉS DU RAPPORT »
// ============================================================================
// - Interrupteur d'activation.
// - Montant à afficher sur le rapport, par section OU par classe.
// - Un champ laissé vide = montant réel (aucun changement pour cette cible).
// - La classe est prioritaire sur la section.
// - ⚡ Bloc « Différence accumulée » : somme de (montant réel - montant du
//   rapport) sur tous les paiements, par section et par classe.
// Retourne true si l'enregistrement a réussi.
// ============================================================================
class _RapportPersonnaliseDialog extends StatefulWidget {
  final FraisScolaires fs;

  const _RapportPersonnaliseDialog({required this.fs});

  @override
  State<_RapportPersonnaliseDialog> createState() =>
      _RapportPersonnaliseDialogState();
}

class _RapportPersonnaliseDialogState
    extends State<_RapportPersonnaliseDialog> {
  late bool _actif;
  String _mode = 'section';
  String? _erreur;
  bool _enregistrement = false;
  late DifferenceRapport _diff;

  final Map<String, TextEditingController> _ctrlSection = {};
  final Map<String, TextEditingController> _ctrlClasse = {};
  final Map<String, String> _sectionDeCle = {};
  final Map<String, String> _classeDeCle = {};

  FraisScolaires get fs => widget.fs;

  String _fmt(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }

  @override
  void initState() {
    super.initState();
    _actif = rapportPersonnalise.actif;
    _diff = fs.differenceAccumuleeRapport();
    for (final section in fs.config.sections) {
      _ctrlSection[section] = TextEditingController(
          text: _fmt(rapportPersonnalise.parSection[section]));
      for (final classe in fs.getClassesForSection(section)) {
        final String cle = RapportPersonnalise.cleClasse(section, classe);
        _sectionDeCle[cle] = section;
        _classeDeCle[cle] = classe;
        _ctrlClasse[cle] = TextEditingController(
            text: _fmt(rapportPersonnalise.parClasse[cle]));
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrlSection.values) {
      c.dispose();
    }
    for (final c in _ctrlClasse.values) {
      c.dispose();
    }
    super.dispose();
  }

  double? _valeur(String texte) {
    final String t =
    texte.trim().replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
    return double.tryParse(t);
  }

  void _toutEffacer() {
    setState(() {
      for (final c in _ctrlSection.values) {
        c.clear();
      }
      for (final c in _ctrlClasse.values) {
        c.clear();
      }
      _erreur = null;
    });
  }

  Future<void> _enregistrer() async {
    final Map<String, double> nouvSection = {};
    final Map<String, double> nouvClasse = {};
    String? erreur;

    for (final entry in _ctrlSection.entries) {
      final String section = entry.key;
      final String texte = entry.value.text.trim();
      if (texte.isEmpty) continue;
      final double? v = _valeur(texte);
      if (v == null || v <= 0) {
        erreur = "Montant invalide pour la section « $section ».";
        break;
      }
      final double ref = fs.montantReferencePourRapport(section);
      if (v > ref + 0.0001) {
        erreur = "Section « $section » : le montant du rapport "
            "(${formatMontant(v)} FC) ne peut pas dépasser le montant réel "
            "(${formatMontant(ref)} FC).";
        break;
      }
      if (v < ref) nouvSection[section] = v;
    }

    if (erreur == null) {
      for (final entry in _ctrlClasse.entries) {
        final String cle = entry.key;
        final String section = _sectionDeCle[cle]!;
        final String classe = _classeDeCle[cle]!;
        final String texte = entry.value.text.trim();
        if (texte.isEmpty) continue;
        final double? v = _valeur(texte);
        if (v == null || v <= 0) {
          erreur = "Montant invalide pour $section › $classe.";
          break;
        }
        final double ref = fs.montantReferencePourRapport(section, classe);
        if (v > ref + 0.0001) {
          erreur = "$section › $classe : le montant du rapport "
              "(${formatMontant(v)} FC) ne peut pas dépasser le montant réel "
              "(${formatMontant(ref)} FC).";
          break;
        }
        if (v < ref) nouvClasse[cle] = v;
      }
    }

    if (erreur != null) {
      setState(() => _erreur = erreur);
      return;
    }

    setState(() {
      _erreur = null;
      _enregistrement = true;
    });

    final bool ancienActif = rapportPersonnalise.actif;
    final Map<String, double> ancienSection =
    Map<String, double>.from(rapportPersonnalise.parSection);
    final Map<String, double> ancienClasse =
    Map<String, double>.from(rapportPersonnalise.parClasse);

    rapportPersonnalise.actif = _actif;
    rapportPersonnalise.parSection = nouvSection;
    rapportPersonnalise.parClasse = nouvClasse;

    final bool ok = await rapportPersonnalise.sauvegarder();
    if (!mounted) return;

    if (!ok) {
      rapportPersonnalise.actif = ancienActif;
      rapportPersonnalise.parSection = ancienSection;
      rapportPersonnalise.parClasse = ancienClasse;
      setState(() {
        _enregistrement = false;
        _erreur = "Échec de l'enregistrement. Réessayez.";
      });
      return;
    }

    Navigator.pop(context, true);
  }

  Widget _ligne({
    required String libelle,
    required double reel,
    required TextEditingController ctrl,
    String note = '',
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(libelle,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  "Montant réel : ${formatMontant(reel)} FC$note",
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 150,
            child: TextField(
              controller: ctrl,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]')),
              ],
              decoration: const InputDecoration(
                labelText: "Sur le rapport",
                suffixText: "FC",
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _lignesSections() {
    return fs.config.sections.map((s) {
      return _ligne(
        libelle: s,
        reel: fs.montantReferencePourRapport(s),
        ctrl: _ctrlSection[s]!,
        note: fs.sectionAFraisConfigure(s) ? '' : ' (frais non configurés)',
      );
    }).toList();
  }

  List<Widget> _lignesClasses() {
    final widgets = <Widget>[];
    for (final section in fs.config.sections) {
      final classes = fs.getClassesForSection(section);
      if (classes.isEmpty) continue;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 2),
        child: Text(
          section,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.indigo,
          ),
        ),
      ));
      for (final classe in classes) {
        final String cle = RapportPersonnalise.cleClasse(section, classe);
        final ctrl = _ctrlClasse[cle];
        if (ctrl == null) continue;
        widgets.add(_ligne(
          libelle: classe,
          reel: fs.montantReferencePourRapport(section, classe),
          ctrl: ctrl,
        ));
      }
    }
    if (widgets.isEmpty) {
      widgets.add(const Text("Aucune classe configurée.",
          style: TextStyle(color: Colors.grey)));
    }
    return widgets;
  }

  // --------------------------------------------------------------------------
  // ⚡ NOUVEAU — bloc « Différence accumulée »
  // --------------------------------------------------------------------------
  Widget _ligneDifference(String libelle, double montant,
      {bool gras = false, double retrait = 0}) {
    return Padding(
      padding: EdgeInsets.only(left: retrait, top: 2, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              libelle,
              style: TextStyle(
                fontSize: gras ? 13 : 12,
                fontWeight: gras ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            "${formatMontant(montant)} FC",
            style: TextStyle(
              fontSize: gras ? 13 : 12,
              fontWeight: gras ? FontWeight.bold : FontWeight.normal,
              color: Colors.deepOrange.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _blocDifference() {
    final List<Widget> lignes = [];

    if (!rapportPersonnalise.enVigueur) {
      lignes.add(const Text(
        "Aucune différence pour le moment : la fonction n'est pas activée "
            "(ou aucun montant n'est enregistré). Activez-la, enregistrez, "
            "puis rouvrez cette fenêtre pour voir la différence.",
        style: TextStyle(fontSize: 12),
      ));
    } else {
      lignes.add(_ligneDifference(
        "TOTAL accumulé (toute l'école)",
        _diff.total,
        gras: true,
      ));
      lignes.add(const Divider(height: 12));

      bool aAuMoinsUneLigne = false;
      final List<String> sectionsOrdonnees = [
        ...fs.config.sections.where((s) => _diff.parSection.containsKey(s)),
        ..._diff.parSection.keys
            .where((s) => !fs.config.sections.contains(s))
            .toList()
          ..sort(),
      ];
      for (final section in sectionsOrdonnees) {
        final double valSection = _diff.parSection[section] ?? 0.0;
        if (valSection.abs() < 0.5) continue;
        aAuMoinsUneLigne = true;
        lignes.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _ligneDifference(section, valSection, gras: true),
        ));
        final classes = _diff.parClasse[section] ?? const <String, double>{};
        final List<String> nomsClasses = classes.keys.toList()..sort();
        for (final classe in nomsClasses) {
          final double v = classes[classe] ?? 0.0;
          if (v.abs() < 0.5) continue;
          lignes.add(_ligneDifference("• $classe", v, retrait: 14));
        }
      }
      if (!aAuMoinsUneLigne) {
        lignes.add(const Text(
          "Aucun paiement concerné pour l'instant.",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ));
      }
      lignes.add(const SizedBox(height: 6));
      lignes.add(const Text(
        "Différence = montant réel payé − montant affiché sur le rapport, "
            "cumulée sur tous les paiements de l'année (calculée avec les "
            "montants enregistrés).",
        style: TextStyle(fontSize: 11, color: Colors.grey),
      ));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.deepOrange.shade50,
        border: Border.all(color: Colors.deepOrange.shade200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Différence accumulée (montant retenu)",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.deepOrange.shade900,
            ),
          ),
          const SizedBox(height: 6),
          ...lignes,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.tune, color: Colors.indigo),
          SizedBox(width: 8),
          Expanded(child: Text("Montants affichés sur le rapport")),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _actif,
                onChanged: (v) => setState(() => _actif = v),
                title: const Text("Activer les montants personnalisés"),
                subtitle: Text(
                  _actif
                      ? "Les rapports PDF afficheront les montants saisis "
                      "ci-dessous."
                      : "Désactivé : les rapports affichent les montants "
                      "réels (comportement normal).",
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const Divider(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "Saisissez le montant mensuel par élève à montrer sur le "
                      "rapport (ex : 60 000 au lieu de 65 000). Les reçus, "
                      "l'historique et toute l'application gardent le montant "
                      "réel. Le montant du rapport doit être inférieur ou "
                      "égal au montant réel. Un champ vide = montant réel. "
                      "Si une section ET une de ses classes sont remplies, "
                      "la classe est prioritaire. Les paiements partiels "
                      "sont affichés proportionnellement.",
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
              _blocDifference(),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'section',
                    label: Text("Par section"),
                    icon: Icon(Icons.account_tree),
                  ),
                  ButtonSegment(
                    value: 'classe',
                    label: Text("Par classe"),
                    icon: Icon(Icons.class_),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 8),
              if (_mode == 'section') ..._lignesSections(),
              if (_mode == 'classe') ..._lignesClasses(),
              if (_erreur != null) ...[
                const SizedBox(height: 12),
                Text(
                  _erreur!,
                  style: const TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enregistrement ? null : _toutEffacer,
          child: const Text("Tout effacer"),
        ),
        TextButton(
          onPressed:
          _enregistrement ? null : () => Navigator.pop(context, false),
          child: const Text("Annuler"),
        ),
        ElevatedButton(
          onPressed: _enregistrement ? null : _enregistrer,
          child: _enregistrement
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Text("Enregistrer"),
        ),
      ],
    );
  }
}