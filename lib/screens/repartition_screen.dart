import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../frais_scolaires.dart';
import '../app_state.dart';

class RepartitionScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const RepartitionScreen({super.key, required this.fraisScolaires});

  @override
  State<RepartitionScreen> createState() => _RepartitionScreenState();
}

class _RepartitionScreenState extends State<RepartitionScreen> {
  FraisScolaires get fraisScolaires => widget.fraisScolaires;

  // ==========================================================================
  // ⚡ VÉRIFICATION MOT DE PASSE (même principe que Paramètres)
  // Sécurise toute sortie de caisse (ajout d'une dépense) et toute
  // suppression d'historique de dépenses.
  // ==========================================================================
  Future<bool> _verifyBackupPassword() async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.backupPassword == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Veuillez d'abord définir un mot de passe de sauvegarde "
                    "(Paramètres) avant de gérer les dépenses.")),
      );
      return false;
    }

    final passController = TextEditingController();
    bool? isCorrect = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Vérification de Sécurité"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                "Entrez votre mot de passe de sauvegarde pour continuer"),
            const SizedBox(height: 15),
            TextField(
              controller: passController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Mot de passe"),
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
                  const SnackBar(content: Text("Mot de passe incorrect")),
                );
              }
            },
            child: const Text("Confirmer"),
          ),
        ],
      ),
    );
    return isCorrect ?? false;
  }

  // ==========================================================================
  // Dialogue : ajouter une nouvelle dépense (motif + montant)
  // ⚡ SÉCURISÉ — demande le mot de passe de sauvegarde avant d'ouvrir le
  // formulaire.
  // ==========================================================================
  Future<void> _startAddDepense() async {
    if (!await _verifyBackupPassword()) return;
    await _openAddDepenseDialog();
  }

  Future<void> _openAddDepenseDialog() async {
    final motifController = TextEditingController();
    final montantController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.money_off, color: Colors.red),
                  SizedBox(width: 8),
                  Text("Nouvelle Dépense"),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: motifController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: "Motif / Justification",
                      hintText:
                      "Ex: Achat de craies, réparation, transport...",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: montantController,
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: "Montant à faire sortir (FC)",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Annuler"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final motif = motifController.text.trim();
                    final montantText =
                    montantController.text.trim().replaceAll(',', '.');
                    final montant = double.tryParse(montantText);

                    if (motif.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                            content: Text("Veuillez indiquer un motif.")),
                      );
                      return;
                    }
                    if (montant == null || montant <= 0) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text("Montant invalide.")),
                      );
                      return;
                    }

                    await fraisScolaires.addDepense(
                      motif: motif,
                      montant: montant,
                    );

                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text("Valider la sortie"),
                ),
              ],
            );
          },
        );
      },
    );
    if (mounted) setState(() {});
  }

  // ==========================================================================
  // Confirmation de suppression d'une dépense (erreur de saisie, etc.)
  // ⚡ SÉCURISÉ — demande le mot de passe de sauvegarde après confirmation.
  // ==========================================================================
  Future<bool> _confirmDeleteDepense(Depense depense) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer cette dépense ?"),
        content: Text(
          "${depense.motif}\n"
              "${depense.montant.toStringAsFixed(0)} FC — ${depense.dateFormatee}",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Supprimer", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return false;
    if (!await _verifyBackupPassword()) return false;
    await fraisScolaires.deleteDepense(depense.id);
    return true;
  }

  // ==========================================================================
  // Vider tout l'historique des dépenses de l'année en cours.
  // Action irréversible : double protection (confirmation + mot de passe).
  // ==========================================================================
  Future<bool> _confirmClearAllDepenses(int count) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text("Tout effacer ?"),
          ],
        ),
        content: Text(
          "Cette action va supprimer DÉFINITIVEMENT les $count dépense(s) "
              "enregistrées pour l'année ${fraisScolaires.currentYear}.\n\n"
              "Cette action est irréversible. Voulez-vous continuer ?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Tout effacer"),
          ),
        ],
      ),
    );
    if (confirm != true) return false;
    if (!await _verifyBackupPassword()) return false;
    await fraisScolaires.clearDepensesForYear();
    return true;
  }

  // ==========================================================================
  // Dialogue : historique complet des dépenses de l'année
  // ==========================================================================
  void _openHistoriqueDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final depenses = fraisScolaires.getDepensesForYear();
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.history, color: Colors.indigo),
                  SizedBox(width: 8),
                  Text("Historique des Dépenses"),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: depenses.isEmpty
                    ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    "Aucune dépense enregistrée pour cette année.",
                    textAlign: TextAlign.center,
                  ),
                )
                    : ListView.separated(
                  shrinkWrap: true,
                  itemCount: depenses.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final d = depenses[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.remove_circle,
                          color: Colors.red),
                      title: Text(d.motif),
                      subtitle: Text(d.dateFormatee,
                          style: const TextStyle(fontSize: 11)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "-${d.montant.toStringAsFixed(0)} FC",
                            style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold),
                          ),
                          InkWell(
                            onTap: () async {
                              final deleted =
                              await _confirmDeleteDepense(d);
                              if (deleted) setDialogState(() {});
                            },
                            child: const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Icon(Icons.delete_outline,
                                  size: 18, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              actions: [
                if (depenses.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    label: const Text("Tout effacer",
                        style: TextStyle(color: Colors.red)),
                    onPressed: () async {
                      final cleared =
                      await _confirmClearAllDepenses(depenses.length);
                      if (cleared) setDialogState(() {});
                    },
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Fermer"),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  // ==========================================================================
  // Ouvre l'écran "Autres Répartitions" (par Option et par Section
  // pédagogique).
  // ==========================================================================
  void _openAutresRepartitions() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _AutresRepartitionsScreen(fraisScolaires: fraisScolaires),
      ),
    );
  }

  // ==========================================================================
  // ⚡ NOUVEAU — Ouvre l'écran "Courbe d'Évolution".
  // ==========================================================================
  void _openEvolution() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _EvolutionScreen(fraisScolaires: fraisScolaires),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalCollecte = fraisScolaires.getYearTotalCollected();
    final totalsByClass = fraisScolaires.getTotalByClass();
    final depenses = fraisScolaires.getDepensesForYear();
    final totalDepenses = fraisScolaires.getTotalDepenses();
    final soldeNet = totalCollecte - totalDepenses;
    final depensesApercu = depenses.take(3).toList();

    return Scaffold(
      appBar: AppBar(title: const Text("Répartition par Administration")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---------------------------------------------------------------
            // Carte Total (enrichie avec dépenses + solde net)
            // ---------------------------------------------------------------
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Total Collecté Global",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text("${totalCollecte.toStringAsFixed(0)} FC",
                        style: const TextStyle(
                            fontSize: 24, color: Colors.green)),
                    if (totalDepenses > 0) ...[
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Total des dépenses",
                              style: TextStyle(color: Colors.black54)),
                          Text("- ${totalDepenses.toStringAsFixed(0)} FC",
                              style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Solde net en caisse",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          Text("${soldeNet.toStringAsFixed(0)} FC",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.indigo)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ---------------------------------------------------------------
            // Boutons Dépenses / Historique
            // ---------------------------------------------------------------
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _startAddDepense,
                    icon: const Icon(Icons.money_off),
                    label: const Text("Dépenses"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openHistoriqueDialog,
                    icon: const Icon(Icons.history),
                    label: const Text("Historique"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Bouton "Autres Répartitions" (par Option et par Section
            // pédagogique).
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openAutresRepartitions,
                icon: const Icon(Icons.account_tree),
                label: const Text("Autres Répartitions"),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  foregroundColor: Colors.indigo,
                  side: const BorderSide(color: Colors.indigo),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ⚡ NOUVEAU — bouton "Courbe d'Évolution".
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openEvolution,
                icon: const Icon(Icons.show_chart),
                label: const Text("Courbe d'Évolution"),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  foregroundColor: Colors.teal.shade700,
                  side: BorderSide(color: Colors.teal.shade700),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ---------------------------------------------------------------
            // Aperçu des dernières dépenses (max 3, sans surcharger l'écran)
            // ---------------------------------------------------------------
            if (depensesApercu.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Dernières Dépenses",
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  if (depenses.length > depensesApercu.length)
                    TextButton(
                      onPressed: _openHistoriqueDialog,
                      child: Text("Voir tout (${depenses.length})"),
                    ),
                ],
              ),
              ...depensesApercu.map((d) => ListTile(
                leading: const Icon(Icons.remove_circle_outline,
                    color: Colors.red),
                title: Text(d.motif),
                subtitle: Text(d.dateFormatee,
                    style: const TextStyle(fontSize: 11)),
                trailing: Text(
                  "-${d.montant.toStringAsFixed(0)} FC",
                  style: const TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold),
                ),
              )),
              const Divider(),
            ],

            // ---------------------------------------------------------------
            // Montant par classe (inchangé)
            // ---------------------------------------------------------------
            const Text("Montant par Classe",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ...totalsByClass.entries.map((entry) => ListTile(
              title: Text(entry.key),
              trailing: Text("${entry.value.toStringAsFixed(0)} FC"),
            )),
            const Divider(),

            // ---------------------------------------------------------------
            // Répartition aux administrations — calculée sur le solde net
            // ---------------------------------------------------------------
            const Text("Répartition aux Administrations",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (totalDepenses > 0)
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  "Calculée sur le solde net (après déduction des dépenses)",
                  style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.black54),
                ),
              ),
            ...fraisScolaires.config.administrations.map((admin) {
              double montant = soldeNet * (admin.pourcentage / 100);
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

// ==============================================================================
// ÉCRAN "AUTRES RÉPARTITIONS"
// Répartition par Option (ex: Primaire / Secondaire / Maternelle) et, à
// l'intérieur d'une option, par Section pédagogique (ex: Électricité,
// Commerciale...) ou "Éducation de Base" pour les classes sans section
// (7ème/8ème dans le système éducatif de la RDC).
// ==============================================================================
class _AutresRepartitionsScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const _AutresRepartitionsScreen({required this.fraisScolaires});

  @override
  State<_AutresRepartitionsScreen> createState() =>
      _AutresRepartitionsScreenState();
}

class _AutresRepartitionsScreenState
    extends State<_AutresRepartitionsScreen> {
  String? selectedOption;

  @override
  void initState() {
    super.initState();
    final options = widget.fraisScolaires.getOptions();
    if (options.isNotEmpty) selectedOption = options.first;
  }

  @override
  Widget build(BuildContext context) {
    final fraisScolaires = widget.fraisScolaires;
    final options = fraisScolaires.getOptions();

    return Scaffold(
      appBar: AppBar(title: const Text("Autres Répartitions")),
      body: options.isEmpty
          ? const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Aucune option/section n'est configurée pour le moment.",
            textAlign: TextAlign.center,
          ),
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.indigo.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "Ces montants sont calculés sur les sommes BRUTES "
                    "collectées par option/section, avant déduction des "
                    "dépenses globales de l'école (les dépenses ne sont "
                    "pas rattachées à une option ou section précise).",
                style: TextStyle(fontSize: 12, color: Colors.indigo),
              ),
            ),
            const SizedBox(height: 16),

            const Text("Vue d'ensemble par Option",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...options.map((option) {
              final detail = fraisScolaires.getRepartitionForOption(option);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(option,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Text(
                    "${detail.total.toStringAsFixed(0)} FC",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                ),
              );
            }),

            const Divider(height: 32),

            const Text("Détail par Option",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: selectedOption,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: "Choisir une option",
                border: OutlineInputBorder(),
              ),
              items: options
                  .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                  .toList(),
              onChanged: (value) => setState(() => selectedOption = value),
            ),
            const SizedBox(height: 16),

            if (selectedOption != null) ...[
              _buildOptionDetail(fraisScolaires, selectedOption!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptionDetail(FraisScolaires fraisScolaires, String option) {
    final detailOption = fraisScolaires.getRepartitionForOption(option);
    final hasSousSections = fraisScolaires.optionHasSousSections(option);
    final sousSections = fraisScolaires.getSousSectionsForOption(option);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: Colors.indigo.withAlpha(15),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Total $option (toutes classes confondues)",
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  "${detailOption.total.toStringAsFixed(0)} FC",
                  style: const TextStyle(
                      fontSize: 22, color: Colors.green,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text("Répartition par administration :",
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ...detailOption.parAdministration.entries.map(
                      (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(e.key),
                        Text("${e.value.toStringAsFixed(0)} FC",
                            style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        if (hasSousSections) ...[
          Text(
            "Détail par Section ($option)",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            "Les classes sans section pédagogique (ex: 7ème, 8ème) "
                "apparaissent sous \"Éducation de Base\".",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          ...sousSections.map((detail) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              title: Text(detail.label,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("${detail.total.toStringAsFixed(0)} FC"),
              children: detail.parAdministration.entries
                  .map(
                    (e) => ListTile(
                  dense: true,
                  title: Text(e.key),
                  trailing: Text("${e.value.toStringAsFixed(0)} FC"),
                ),
              )
                  .toList(),
            ),
          )),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              "Aucune section pédagogique définie pour \"$option\" — "
                  "le total ci-dessus représente déjà l'ensemble de "
                  "l'option.",
              style: const TextStyle(
                  color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ),
      ],
    );
  }
}

// ==============================================================================
// ⚡ NOUVEAU — ÉCRAN "COURBE D'ÉVOLUTION"
// Courbe mensuelle (Septembre → Juin) des montants collectés, comme un
// graphique en ligne Excel classique. Filtrable par Option, Section
// pédagogique (ou "Éducation de Base" pour 7ème/8ème) et Classe.
// ==============================================================================
class _EvolutionScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const _EvolutionScreen({required this.fraisScolaires});

  @override
  State<_EvolutionScreen> createState() => _EvolutionScreenState();
}

class _EvolutionScreenState extends State<_EvolutionScreen> {
  String? selectedOption;      // null = toute l'école
  String? selectedSousSection; // null = toutes les sections
  String? selectedClasse;      // null = toutes les classes
  bool cumulatif = false;

  static const List<String> _moisCourts = [
    'Sep', 'Oct', 'Nov', 'Déc', 'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Jun'
  ];

  void _onOptionChanged(String? value) {
    setState(() {
      selectedOption = value;
      selectedSousSection = null;
      selectedClasse = null;
    });
  }

  void _onSousSectionChanged(String? value) {
    setState(() {
      selectedSousSection = value;
      selectedClasse = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fraisScolaires = widget.fraisScolaires;
    final options = fraisScolaires.getOptions();

    final bool hasSousSections = selectedOption != null &&
        fraisScolaires.optionHasSousSections(selectedOption!);
    final sousSections = selectedOption != null
        ? fraisScolaires.getSousSectionsForOption(selectedOption!)
        : <RepartitionDetail>[];

    final classesOptions = selectedOption != null
        ? fraisScolaires.getClassesForOptionAndSousSection(
        selectedOption!, selectedSousSection)
        : <String>[];

    final rawValues = fraisScolaires.getMonthlyEvolution(
      option: selectedOption,
      sousSectionLabel: selectedSousSection,
      classe: selectedClasse,
    );

    final List<double> displayValues;
    if (cumulatif) {
      double running = 0;
      displayValues = rawValues.map((v) {
        running += v;
        return running;
      }).toList();
    } else {
      displayValues = rawValues;
    }

    final double total = rawValues.fold(0.0, (a, b) => a + b);
    final double maxY = displayValues.isEmpty
        ? 100
        : (displayValues.reduce((a, b) => a > b ? a : b) * 1.2)
        .clamp(100, double.infinity);

    String scopeLabel = "Toute l'école";
    if (selectedOption != null) {
      scopeLabel = selectedOption!;
      if (selectedSousSection != null) {
        scopeLabel += " — $selectedSousSection";
      }
      if (selectedClasse != null) {
        scopeLabel += " — $selectedClasse";
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Courbe d'Évolution")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ------------------------------------------------------------
            // Filtres
            // ------------------------------------------------------------
            const Text("Filtrer la courbe",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: selectedOption,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: "Option",
                border: OutlineInputBorder(),
              ),
              hint: const Text("Toute l'école"),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text("Toute l'école")),
                ...options.map(
                        (o) => DropdownMenuItem(value: o, child: Text(o))),
              ],
              onChanged: _onOptionChanged,
            ),
            if (selectedOption != null && hasSousSections) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selectedSousSection,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: "Section pédagogique",
                  border: OutlineInputBorder(),
                ),
                hint: const Text("Toutes les sections"),
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text("Toutes les sections")),
                  ...sousSections.map(
                        (s) => DropdownMenuItem(
                        value: s.label, child: Text(s.label)),
                  ),
                ],
                onChanged: _onSousSectionChanged,
              ),
            ],
            if (selectedOption != null && classesOptions.isNotEmpty) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selectedClasse,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: "Classe",
                  border: OutlineInputBorder(),
                ),
                hint: const Text("Toutes les classes"),
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text("Toutes les classes")),
                  ...classesOptions.map(
                        (c) => DropdownMenuItem(value: c, child: Text(c)),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => selectedClasse = value),
              ),
            ],
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Vue cumulée"),
              subtitle: const Text(
                "Somme progressive mois après mois, au lieu du montant "
                    "de chaque mois seul.",
                style: TextStyle(fontSize: 11),
              ),
              value: cumulatif,
              onChanged: (value) => setState(() => cumulatif = value),
            ),

            const Divider(height: 32),

            // ------------------------------------------------------------
            // Résumé
            // ------------------------------------------------------------
            Text(
              scopeLabel,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
            ),
            const SizedBox(height: 4),
            Text(
              "Total sur la période : ${total.toStringAsFixed(0)} FC",
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 20),

            // ------------------------------------------------------------
            // Courbe
            // ------------------------------------------------------------
            if (total == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    "Aucune donnée de paiement pour cette sélection.",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              SizedBox(
                height: 320,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16, top: 8),
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: (fraisScolaires.months.length - 1).toDouble(),
                      minY: 0,
                      maxY: maxY,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxY / 4,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.grey.withAlpha(60),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade400),
                          left: BorderSide(color: Colors.grey.shade400),
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= _moisCourts.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  _moisCourts[i],
                                  style: const TextStyle(fontSize: 11),
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 56,
                            interval: maxY / 4,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                value >= 1000
                                    ? "${(value / 1000).toStringAsFixed(0)}k"
                                    : value.toStringAsFixed(0),
                                style: const TextStyle(fontSize: 10),
                              );
                            },
                          ),
                        ),
                      ),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (spots) => spots.map((s) {
                            final i = s.x.toInt();
                            final label = (i >= 0 && i < _moisCourts.length)
                                ? _moisCourts[i]
                                : '';
                            return LineTooltipItem(
                              "$label\n${s.y.toStringAsFixed(0)} FC",
                              const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            );
                          }).toList(),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (int i = 0; i < displayValues.length; i++)
                              FlSpot(i.toDouble(), displayValues[i]),
                          ],
                          isCurved: true,
                          curveSmoothness: 0.25,
                          color: Colors.indigo,
                          barWidth: 3,
                          dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(
                            show: true,
                            color: Colors.indigo.withAlpha(30),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}