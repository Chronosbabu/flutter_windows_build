import 'package:flutter/material.dart';
import '../frais_scolaires.dart';
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
  //
  // Quand promotionMode est actif, chaque élève de la liste affiche deux
  // cases à cocher au lieu de son ID :
  //   - "Passe" : l'élève sera copié dans la nouvelle année (décochée =
  //     abandon, l'élève ne sera pas transféré).
  //   - "Monte" : l'élève monte à la classe supérieure dans la nouvelle
  //     année (décochée = redoublant, il reste dans la même classe).
  //
  // Les deux cases sont cochées par défaut pour TOUS les élèves de
  // l'année actuelle (pas seulement ceux affichés par le filtre courant),
  // afin que changer le filtre de recherche ne fasse perdre aucune
  // sélection déjà faite par l'utilisateur.
  bool promotionMode = false;
  String? targetPromotionYear;
  final Map<String, bool> passToNextYear = {};
  final Map<String, bool> monterClasse = {};

  @override
  Widget build(BuildContext context) {
    final allEleves = widget.fraisScolaires.currentData.eleves;
    final filteredEleves = allEleves.where((eleve) {
      final matchesSearch = eleve.nom.toLowerCase().contains(searchQuery.toLowerCase()) ||
          eleve.postNom.toLowerCase().contains(searchQuery.toLowerCase()) ||
          eleve.prenom.toLowerCase().contains(searchQuery.toLowerCase()) ||
          eleve.id.toLowerCase().contains(searchQuery.toLowerCase());
      final matchesSection = selectedSectionFilter == null || eleve.section == selectedSectionFilter;
      final matchesClass = selectedClassFilter == null || eleve.classe == selectedClassFilter;
      return matchesSearch && matchesSection && matchesClass;
    }).toList();

    // ==================== CLASSES DISPONIBLES POUR LE FILTRE ====================
    // Avant : la liste des classes du filtre venait uniquement des élèves déjà
    // enregistrés (impossible de filtrer par une classe qui n'a encore aucun
    // élève, et les nouvelles classes/sous-classes ajoutées n'apparaissaient
    // pas tant qu'aucun élève n'y était inscrit).
    //
    // Maintenant : on utilise la liste centrale et complète (numéros de
    // classe automatiques + sous-classes manuelles), pour la section choisie,
    // ou pour toutes les sections si aucune n'est sélectionnée.
    final classOptions = selectedSectionFilter != null
        ? List<String>.from(widget.fraisScolaires.getAllDisplayClassesForSection(selectedSectionFilter!))
        : List<String>.from(widget.fraisScolaires.getAllDisplayClasses());
    if (selectedClassFilter != null && !classOptions.contains(selectedClassFilter)) {
      classOptions.add(selectedClassFilter!);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(promotionMode
            ? "Passation vers $targetPromotionYear"
            : "Registre des Élèves"),
        actions: promotionMode
            ? [
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
        ]
            : [
          IconButton(
            icon: const Icon(Icons.move_up),
            tooltip: "Passation vers la nouvelle année",
            onPressed: _startPromotionMode,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Télécharger la liste en PDF",
            onPressed: () => _downloadCurrentListAsPdf(),
          ),
        ],
      ),
      floatingActionButton: promotionMode
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
                      const DropdownMenuItem(value: null, child: Text("Toutes Sections")),
                      ...widget.fraisScolaires.config.sections
                          .map((s) => DropdownMenuItem(value: s, child: Text(s))),
                    ],
                    onChanged: (val) {
                      setState(() {
                        selectedSectionFilter = val;
                        // La liste des classes valides change avec la section :
                        // on réinitialise le filtre classe s'il n'est plus valide.
                        final validClasses = val != null
                            ? widget.fraisScolaires.getAllDisplayClassesForSection(val)
                            : widget.fraisScolaires.getAllDisplayClasses();
                        if (selectedClassFilter != null && !validClasses.contains(selectedClassFilter)) {
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
                      const DropdownMenuItem(value: null, child: Text("Toutes Classes")),
                      ...classOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                    ],
                    onChanged: (val) => setState(() => selectedClassFilter = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              "Total : ${filteredEleves.length} élèves",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filteredEleves.isEmpty
                  ? const Center(child: Text("Aucun élève trouvé"))
                  : ListView.builder(
                itemCount: filteredEleves.length,
                itemBuilder: (context, index) {
                  final e = filteredEleves[index];
                  return promotionMode
                      ? _buildPromotionCard(e)
                      : _buildNormalCard(e);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== CARTE NORMALE (HORS PASSATION) ====================
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
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
        ),
      ),
    );
  }

  // ==================== BANNIÈRE D'INFORMATION (MODE PASSATION) ====================
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

  // ==================== CARTE AVEC CASES À COCHER (MODE PASSATION) ====================
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
                      // "Monte" n'a de sens que si l'élève passe à la nouvelle
                      // année ; on désactive la case sinon (mais on garde sa
                      // valeur en mémoire au cas où l'utilisateur recoche "Passe").
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

  // ==================== ACTIONS EN MASSE (BOUTONS DE LA BANNIÈRE) ====================
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
                        .map((y) => DropdownMenuItem(value: y, child: Text(y)))
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
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
      // On initialise la sélection pour TOUS les élèves de l'année actuelle
      // (pas seulement ceux visibles avec le filtre courant), pour que la
      // recherche/le filtre n'affecte jamais les choix déjà faits.
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Confirmer")),
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

  // ==================== TÉLÉCHARGEMENT PDF DE LA LISTE ACTUELLE ====================
  Future<void> _downloadCurrentListAsPdf() async {
    final String sectionText = selectedSectionFilter ?? "Toutes_Sections";
    final String classText = selectedClassFilter ?? "Toutes_Classes";
    final filename = "Liste_Eleves_${sectionText}_${classText}_${DateTime.now().toString().split(' ')[0]}";

    await widget.fraisScolaires.generatePdf(
      filename: filename,
      reportType: "student_list",
      sectionFilter: selectedSectionFilter,
      classFilter: selectedClassFilter,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Liste des élèves téléchargée en PDF")),
      );
    }
  }
}