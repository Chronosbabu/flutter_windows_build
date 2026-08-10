import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../frais_scolaires.dart';
import '../app_state.dart';
import '../models.dart';

class StudentListScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const StudentListScreen({super.key, required this.fraisScolaires});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  String searchQuery = "";
  String? selectedSectionFilter;
  String? selectedClassFilter;

  // ====================================================================
  // MODE PASSATION VERS LA NOUVELLE ANNÉE
  // ====================================================================
  bool promotionMode = false;
  String? targetPromotionYear;
  final Map<String, bool> passToNextYear = {};
  final Map<String, bool> monterClasse = {};

  // ====================================================================
  // MODE SUPPRESSION D'ÉLÈVE
  // ====================================================================
  //
  // Quand deletionMode est actif, l'AppBar change de titre, les filtres
  // et la barre de recherche restent actifs (pour trouver rapidement
  // l'élève à supprimer), et chaque carte affiche un bouton de corbeille
  // rouge à droite. Un seul appui sur la corbeille déclenche la
  // vérification du mot de passe admin puis la confirmation avant
  // suppression définitive.
  bool deletionMode = false;

  @override
  Widget build(BuildContext context) {
    final allEleves = widget.fraisScolaires.currentData.eleves;
    final filteredEleves = allEleves.where((eleve) {
      final matchesSearch =
          eleve.nom.toLowerCase().contains(searchQuery.toLowerCase()) ||
              eleve.postNom.toLowerCase().contains(searchQuery.toLowerCase()) ||
              eleve.prenom.toLowerCase().contains(searchQuery.toLowerCase()) ||
              eleve.id.toLowerCase().contains(searchQuery.toLowerCase());
      final matchesSection =
          selectedSectionFilter == null || eleve.section == selectedSectionFilter;
      final matchesClass =
          selectedClassFilter == null || eleve.classe == selectedClassFilter;
      return matchesSearch && matchesSection && matchesClass;
    }).toList();

    final classOptions = selectedSectionFilter != null
        ? List<String>.from(
        widget.fraisScolaires.getAllDisplayClassesForSection(selectedSectionFilter!))
        : List<String>.from(widget.fraisScolaires.getAllDisplayClasses());
    if (selectedClassFilter != null && !classOptions.contains(selectedClassFilter)) {
      classOptions.add(selectedClassFilter!);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          promotionMode
              ? "Passation vers $targetPromotionYear"
              : deletionMode
              ? "Sélectionner un élève à supprimer"
              : "Registre des Élèves",
        ),
        actions: _buildAppBarActions(),
      ),
      floatingActionButton: (promotionMode || deletionMode)
          ? null
          : FloatingActionButton(
        onPressed: () => _downloadCurrentListAsPdf(),
        tooltip: "Télécharger PDF",
        child: const Icon(Icons.download),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (promotionMode) _buildPromotionBanner(),
            if (deletionMode) _buildDeletionBanner(),
            TextField(
              decoration: const InputDecoration(
                labelText: "Rechercher par nom, post-nom, ID...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() => searchQuery = value);
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text("Toutes Sections"),
                    value: selectedSectionFilter,
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text("Toutes Sections")),
                      ...widget.fraisScolaires.config.sections
                          .map((s) => DropdownMenuItem(value: s, child: Text(s))),
                    ],
                    onChanged: (val) {
                      setState(() {
                        selectedSectionFilter = val;
                        final validClasses = val != null
                            ? widget.fraisScolaires
                            .getAllDisplayClassesForSection(val)
                            : widget.fraisScolaires.getAllDisplayClasses();
                        if (selectedClassFilter != null &&
                            !validClasses.contains(selectedClassFilter)) {
                          selectedClassFilter = null;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text("Toutes Classes"),
                    value: selectedClassFilter,
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text("Toutes Classes")),
                      ...classOptions
                          .map((c) => DropdownMenuItem(value: c, child: Text(c))),
                    ],
                    onChanged: (val) =>
                        setState(() => selectedClassFilter = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              "Total : ${filteredEleves.length} élève(s)",
              style:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filteredEleves.isEmpty
                  ? const Center(child: Text("Aucun élève trouvé"))
                  : ListView.builder(
                itemCount: filteredEleves.length,
                itemBuilder: (context, index) {
                  final e = filteredEleves[index];
                  if (promotionMode) return _buildPromotionCard(e);
                  if (deletionMode) return _buildDeletionCard(e);
                  return _buildNormalCard(e);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ACTIONS APPBAR ====================
  List<Widget> _buildAppBarActions() {
    if (promotionMode) {
      return [
        IconButton(
          icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
          tooltip: "Valider la passation",
          onPressed: _validatePromotion,
        ),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: "Annuler la passation",
          onPressed: _cancelPromotionMode,
        ),
      ];
    }

    if (deletionMode) {
      return [
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: "Quitter le mode suppression",
          onPressed: _cancelDeletionMode,
        ),
      ];
    }

    // Mode normal : 3 boutons côte à côte
    return [
      IconButton(
        icon: const Icon(Icons.move_up),
        tooltip: "Passation vers la nouvelle année",
        onPressed: _startPromotionMode,
      ),
      IconButton(
        icon: const Icon(Icons.delete_forever, color: Colors.red),
        tooltip: "Supprimer un élève",
        onPressed: _startDeletionMode,
      ),
      IconButton(
        icon: const Icon(Icons.picture_as_pdf),
        tooltip: "Télécharger la liste en PDF",
        onPressed: () => _downloadCurrentListAsPdf(),
      ),
    ];
  }

  // ==================== CARTE NORMALE (HORS MODES SPÉCIAUX) ====================
  Widget _buildNormalCard(Eleve e) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            e.id.isNotEmpty ? e.id.substring(0, 2) : "?",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        title: Text("${e.nom} ${e.postNom} ${e.prenom}"),
        subtitle: Text("${e.section} - ${e.classe}"),
        trailing: Text(
          e.id,
          style: const TextStyle(
              fontWeight: FontWeight.bold, color: Colors.indigo),
        ),
      ),
    );
  }

  // ====================================================================
  // MODE SUPPRESSION — bannière + carte
  // ====================================================================

  Widget _buildDeletionBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.35)),
      ),
      child: Row(
        children: const [
          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Utilisez la recherche ou les filtres ci-dessous pour trouver "
                  "l'élève à supprimer, puis appuyez sur la corbeille 🗑 à côté "
                  "de son nom. Le mot de passe administrateur sera demandé.",
              style: TextStyle(fontSize: 12.5, color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeletionCard(Eleve e) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.red.shade50,
          child: Text(
            e.id.isNotEmpty ? e.id.substring(0, 2) : "?",
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.red),
          ),
        ),
        title: Text("${e.nom} ${e.postNom} ${e.prenom}"),
        subtitle: Text("${e.section} - ${e.classe}  |  ID : ${e.id}"),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red, size: 28),
          tooltip: "Supprimer cet élève",
          onPressed: () => _requestDeleteStudent(e),
        ),
      ),
    );
  }

  // ==================== DÉMARRER / QUITTER LE MODE SUPPRESSION ====================
  void _startDeletionMode() {
    setState(() {
      deletionMode = true;
      // Réinitialiser la recherche pour partir d'une ardoise vide
      searchQuery = "";
    });
  }

  void _cancelDeletionMode() {
    setState(() {
      deletionMode = false;
      searchQuery = "";
    });
  }

  // ==================== SUPPRESSION SÉCURISÉE D'UN ÉLÈVE ====================
  //
  // Flux complet :
  //   1. Vérification du mot de passe administrateur (backupPassword de
  //      AppState, le même que pour les autres actions sensibles).
  //   2. Boîte de dialogue d'avertissement avec les informations de
  //      l'élève et rappel que la suppression est IRRÉVERSIBLE.
  //   3. Si l'utilisateur confirme, l'élève est retiré de
  //      currentData.eleves et les données sont sauvegardées localement.
  //   4. Toutes les autres pages (PaiementEleveScreen, etc.) lisent
  //      currentData.eleves en direct : elles se mettent à jour
  //      automatiquement à leur prochain rebuild.
  //   5. Un message snackbar rappelle de sauvegarder sur le serveur pour
  //      propager la suppression à distance.
  Future<void> _requestDeleteStudent(Eleve eleve) async {
    // --- Étape 1 : Vérification du mot de passe admin ---
    final appState = Provider.of<AppState>(context, listen: false);

    if (appState.backupPassword == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Aucun mot de passe administrateur défini. "
                  "Définissez-en un dans les Paramètres avant de supprimer un élève."),
        ),
      );
      return;
    }

    final passController = TextEditingController();
    final bool? passwordOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Vérification Administrateur"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Entrez le mot de passe administrateur pour continuer.",
            ),
            const SizedBox(height: 14),
            TextField(
              controller: passController,
              obscureText: true,
              decoration:
              const InputDecoration(labelText: "Mot de passe"),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              if (passController.text.trim() == appState.backupPassword) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Mot de passe incorrect.")),
                );
              }
            },
            child: const Text("Confirmer"),
          ),
        ],
      ),
    );

    if (passwordOk != true) return;

    // --- Étape 2 : Avertissement et confirmation de suppression ---
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 26),
            SizedBox(width: 8),
            Text("Suppression irréversible",
                style: TextStyle(color: Colors.red)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Vous êtes sur le point de supprimer définitivement l'élève "
                  "suivant de l'année scolaire en cours :",
              style: TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${eleve.nom} ${eleve.postNom} ${eleve.prenom}",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text("ID : ${eleve.id}"),
                  Text(
                      "Classe : ${eleve.classe}  |  Section : ${eleve.section}"),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              "⚠️  Cette action supprime l'élève ET tout son historique de "
                  "paiements pour cette année. Elle ne peut pas être annulée.\n\n"
                  "Après suppression, pensez à sauvegarder sur le serveur "
                  "(Paramètres → Sauvegarder sur le Serveur) pour que la "
                  "modification soit prise en compte sur tous les appareils.",
              style: TextStyle(fontSize: 12.5, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Supprimer définitivement",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // --- Étape 3 : Suppression locale et sauvegarde ---
    setState(() {
      widget.fraisScolaires.currentData.eleves
          .removeWhere((e) => e.id == eleve.id);
    });
    await widget.fraisScolaires.saveData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "✅ ${eleve.nom} ${eleve.postNom} ${eleve.prenom} a été supprimé(e). "
                "Pensez à sauvegarder sur le serveur dans Paramètres.",
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  // ====================================================================
  // MODE PASSATION — bannière + carte (inchangés)
  // ====================================================================

  Widget _buildPromotionBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.indigo.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Passation vers \"$targetPromotionYear\"",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            "Toutes les cases sont cochées par défaut. Décochez \"Passe\" pour "
                "un abandon (l'élève ne sera pas transféré). Décochez \"Monte\" "
                "pour un redoublant (il garde la même classe). Appuyez ensuite "
                "sur ✅ en haut pour valider.",
            style: TextStyle(fontSize: 12.5, color: Colors.black87),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.check_box, size: 18),
                label: const Text("Tous passent"),
                onPressed: () => _bulkSetPass(true),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.check_box_outline_blank, size: 18),
                label: const Text("Aucun ne passe"),
                onPressed: () => _bulkSetPass(false),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.arrow_upward, size: 18),
                label: const Text("Tous montent"),
                onPressed: () => _bulkSetMonter(true),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.horizontal_rule, size: 18),
                label: const Text("Aucun ne monte"),
                onPressed: () => _bulkSetMonter(false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPromotionCard(Eleve e) {
    final bool passe = passToNextYear[e.id] ?? true;
    final bool monte = monterClasse[e.id] ?? true;
    final String classeApercu = passe
        ? (monte ? widget.fraisScolaires.computePromotedClasse(e) : e.classe)
        : "—";

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            CircleAvatar(
              child: Text(
                e.id.isNotEmpty ? e.id.substring(0, 2) : "?",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${e.nom} ${e.postNom} ${e.prenom}",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    "${e.section} - ${e.classe}  →  $classeApercu",
                    style: TextStyle(
                      fontSize: 12.5,
                      color: passe ? Colors.indigo : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Passe", style: TextStyle(fontSize: 11)),
                    Checkbox(
                      value: passe,
                      onChanged: (v) => setState(() {
                        passToNextYear[e.id] = v ?? true;
                      }),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Monte", style: TextStyle(fontSize: 11)),
                    Checkbox(
                      value: monte,
                      onChanged: !passe
                          ? null
                          : (v) => setState(() {
                        monterClasse[e.id] = v ?? true;
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ACTIONS EN MASSE (PASSATION) ====================
  void _bulkSetPass(bool value) {
    setState(() {
      for (var e in widget.fraisScolaires.currentData.eleves) {
        passToNextYear[e.id] = value;
      }
    });
  }

  void _bulkSetMonter(bool value) {
    setState(() {
      for (var e in widget.fraisScolaires.currentData.eleves) {
        monterClasse[e.id] = value;
      }
    });
  }

  // ==================== DÉMARRER LE MODE PASSATION ====================
  void _startPromotionMode() async {
    final years = widget.fraisScolaires.history.keys
        .where((y) => y != widget.fraisScolaires.currentYear)
        .toList();

    String? chosenYear;
    final newYearController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Passation vers la nouvelle année"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Choisissez une année scolaire déjà créée dans les "
                      "Paramètres, ou tapez directement le nom d'une "
                      "nouvelle année à créer.",
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 14),
                if (years.isNotEmpty) ...[
                  DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text("Choisir une année existante"),
                    value: chosenYear,
                    items: years
                        .map((y) =>
                        DropdownMenuItem(value: y, child: Text(y)))
                        .toList(),
                    onChanged: (v) => setStateDialog(() {
                      chosenYear = v;
                      newYearController.clear();
                    }),
                  ),
                  const SizedBox(height: 14),
                  const Text("— ou —", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: newYearController,
                  decoration: const InputDecoration(
                    labelText: "Nouvelle année (ex: 2026-2027)",
                  ),
                  onChanged: (_) => setStateDialog(() => chosenYear = null),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Annuler")),
            ElevatedButton(
              onPressed: () {
                final value = chosenYear ?? newYearController.text.trim();
                if (value.isEmpty) return;
                Navigator.pop(ctx, value);
              },
              child: const Text("Continuer"),
            ),
          ],
        ),
      ),
    );

    if (result == null || result.isEmpty) return;

    setState(() {
      promotionMode = true;
      targetPromotionYear = result;
      passToNextYear.clear();
      monterClasse.clear();
      for (var e in widget.fraisScolaires.currentData.eleves) {
        passToNextYear[e.id] = true;
        monterClasse[e.id] = true;
      }
    });
  }

  // ==================== ANNULER LE MODE PASSATION ====================
  void _cancelPromotionMode() {
    setState(() {
      promotionMode = false;
      targetPromotionYear = null;
      passToNextYear.clear();
      monterClasse.clear();
    });
  }

  // ==================== VALIDER LA PASSATION ====================
  void _validatePromotion() async {
    if (targetPromotionYear == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmer la passation"),
        content: Text(
          "Les élèves cochés \"Passe\" vont être copiés dans l'année "
              "\"$targetPromotionYear\", avec leur classe supérieure si "
              "\"Monte\" est cochée. Cette action ne supprime ni ne modifie "
              "rien dans l'année actuelle (${widget.fraisScolaires.currentYear}). "
              "Voulez-vous continuer ?",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Confirmer")),
        ],
      ),
    );
    if (confirm != true) return;

    final result = await widget.fraisScolaires.promoteStudents(
      studentsToProcess: widget.fraisScolaires.currentData.eleves,
      passToNextYear: passToNextYear,
      monterClasse: monterClasse,
      targetYear: targetPromotionYear!,
    );

    if (mounted) {
      final year = targetPromotionYear;
      setState(() {
        promotionMode = false;
        targetPromotionYear = null;
        passToNextYear.clear();
        monterClasse.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "✅ ${result['promoted']} élève(s) envoyé(s) vers \"$year\" "
                "(${result['redoublants']} sans changement de classe), "
                "${result['abandoned']} non transféré(s) (abandons). "
                "Pensez à sauvegarder sur le serveur dans Paramètres.",
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  // ==================== TÉLÉCHARGEMENT PDF ====================
  Future<void> _downloadCurrentListAsPdf() async {
    final String sectionText = selectedSectionFilter ?? "Toutes_Sections";
    final String classText = selectedClassFilter ?? "Toutes_Classes";
    final filename =
        "Liste_Eleves_${sectionText}_${classText}_${DateTime.now().toString().split(' ')[0]}";

    await widget.fraisScolaires.generatePdf(
      filename: filename,
      reportType: "student_list",
      sectionFilter: selectedSectionFilter,
      classFilter: selectedClassFilter,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("✅ Liste des élèves téléchargée en PDF")),
      );
    }
  }
}