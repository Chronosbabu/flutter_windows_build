import 'package:flutter/material.dart';
import '../frais_scolaires.dart';
import '../models.dart';

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

  // ⚡ NOUVEAU — Filtres optionnels Section / Classe pour la fenêtre de
  // paiement. Ils ne changent JAMAIS l'éligibilité au frais (celle-ci
  // reste définie par le scope du frais dans les Paramètres) : ils
  // servent uniquement à naviguer plus facilement dans la liste des
  // élèves et à consulter la répartition par administration limitée à
  // une section/classe précise (voir `_showAdminRepartitionDialog`).
  String? filterSection;
  String? filterClasse;

  @override
  void initState() {
    super.initState();
    final frais = widget.fraisScolaires.getAutresFrais();
    if (frais.isNotEmpty) selectedFrais = frais.first;
    searchController.addListener(() => setState(() {}));
    // ⚡ NOUVEAU — vide la file d'attente des reçus non encore imprimés à
    // l'ouverture de l'écran (voir FraisScolaires.flushReceiptQueue). Cela
    // fonctionne même si l'imprimante était débranchée au moment du
    // paiement et que l'application/l'ordinateur a été éteint entretemps.
    _flushPendingReceipts();
  }

  // ⚡ NOUVEAU
  Future<void> _flushPendingReceipts() async {
    final count = await widget.fraisScolaires.flushReceiptQueue();
    if (mounted && count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "🖨️ $count reçu(s) en attente ont été imprimés automatiquement."),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<Eleve> get _eligibleFiltered {
    if (selectedFrais == null) return [];
    final query = searchController.text.toLowerCase().trim();
    var eligible =
    widget.fraisScolaires.getEligibleStudentsForAutreFrais(selectedFrais!);

    // ⚡ NOUVEAU — filtres Section/Classe, purement pour la navigation
    // dans cette fenêtre de paiement (n'affecte jamais l'éligibilité
    // définie dans les Paramètres).
    if (filterSection != null) {
      eligible = eligible.where((e) => e.section == filterSection).toList();
    }
    if (filterClasse != null) {
      eligible = eligible.where((e) => e.classe == filterClasse).toList();
    }

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

  // ==========================================================================
  // ⚡ CORRIGÉ — L'IMPRESSION PASSE DÉSORMAIS EXCLUSIVEMENT PAR LE SYSTÈME
  // CENTRALISÉ ANTI-DOUBLON + FILE D'ATTENTE DE FraisScolaires
  // (`printOrQueueAutreFraisReceipt`). Un reçu déjà imprimé pour cet élève
  // et ce frais précis ne sera plus jamais réimprimé automatiquement, d'où
  // que vienne la demande. Si aucune imprimante n'est branchée, le reçu
  // reste en attente et sort automatiquement dès qu'une imprimante devient
  // disponible (voir `flushReceiptQueue`, appelée à l'ouverture de l'écran).
  //
  // ⚡ SUR DEMANDE DE LA DIRECTION — tous les boutons de réimpression
  // manuelle ont été retirés de cet écran (le personnel se trompait avec
  // des reçus réimprimés plus tard). La SEULE impression possible est
  // désormais automatique, immédiatement après le paiement.
  //
  // ⚡ CE COMPORTEMENT N'A PAS CHANGÉ dans cette version : la génération de
  // reçu pour les "Autres Frais" continue de fonctionner exactement comme
  // pour les frais principaux (anti-doublon via `printedReceiptKeys`, mise
  // en file d'attente via `receiptQueue` si aucune imprimante n'est
  // disponible, impression automatique différée via `flushReceiptQueue`).
  // Le montant réellement imprimé/enregistré est désormais toujours celui
  // résolu pour CET élève précis (voir `getMontantAutreFraisPourEleve`),
  // qui peut varier selon sa section/classe si des exceptions ont été
  // configurées pour ce frais.
  // ==========================================================================

  Future<void> _payerUnSeul(Eleve eleve) async {
    if (selectedFrais == null) return;
    if (widget.fraisScolaires.hasPaidAutreFrais(eleve, selectedFrais!)) return;
    setState(() => _processing = true);
    final frais = selectedFrais!;
    await widget.fraisScolaires.payAutreFrais(frais: frais, eleve: eleve);
    final printed = await widget.fraisScolaires.printOrQueueAutreFraisReceipt(
      eleve: eleve,
      frais: frais,
    );
    if (mounted) {
      setState(() {
        selectedStudentIds.remove(eleve.id);
        _processing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            printed
                ? "✅ ${frais.nom} enregistré et reçu imprimé pour ${eleve.nom} ${eleve.prenom}"
                : "✅ ${frais.nom} enregistré pour ${eleve.nom} ${eleve.prenom} — reçu en attente d'impression",
          ),
        ),
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
    int printedCount = 0;
    for (final eleve in students) {
      if (widget.fraisScolaires.hasPaidAutreFrais(eleve, frais)) continue;
      await widget.fraisScolaires.payAutreFrais(frais: frais, eleve: eleve);
      success++;
      final printed = await widget.fraisScolaires.printOrQueueAutreFraisReceipt(
        eleve: eleve,
        frais: frais,
      );
      if (printed) printedCount++;
    }

    if (mounted) {
      setState(() {
        selectedStudentIds.clear();
        _processing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "✅ Paiement de \"${frais.nom}\" enregistré pour $success élève(s)"
                "${printedCount < success ? ' ($printedCount reçu(s) imprimé(s), le reste en attente)' : (success > 0 ? ' — tous les reçus imprimés' : '')}",
          ),
        ),
      );
    }
  }

  void _confirmPaiementUnique(Eleve eleve) {
    if (selectedFrais == null) return;
    // ⚡ NOUVEAU — montant réellement dû par CET élève (peut varier selon
    // sa section/classe, voir FraisScolaires.getMontantAutreFraisPourEleve),
    // affiché ici au lieu du montant unique `selectedFrais!.montant`.
    final double montant = widget.fraisScolaires
        .getMontantAutreFraisPourEleve(selectedFrais!, eleve);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(selectedFrais!.nom),
        content: Text(
          "Confirmer le paiement de "
              "${montant.toStringAsFixed(0)} FC pour "
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

  // ==========================================================================
  // TOTAUX PAR CLASSE ET PAR OPTION POUR LE FRAIS SÉLECTIONNÉ (inchangé —
  // n'a rien à voir avec l'impression, purement informatif).
  // ==========================================================================
  Map<String, double> _totalsByClasseForSelected() {
    final totals = <String, double>{};
    if (selectedFrais == null) return totals;
    final paiements = widget.fraisScolaires
        .getAutresFraisPaiementsForYear()
        .where((p) => p.autreFraisId == selectedFrais!.id);
    for (final p in paiements) {
      Eleve? eleve;
      for (final e in widget.fraisScolaires.currentData.eleves) {
        if (e.id == p.eleveId) {
          eleve = e;
          break;
        }
      }
      final label = eleve != null ? eleve.classe : "Élève(s) introuvable(s)";
      totals[label] = (totals[label] ?? 0) + p.montant;
    }
    return totals;
  }

  Map<String, double> _totalsByOptionForSelected() {
    final totals = <String, double>{};
    if (selectedFrais == null) return totals;
    final paiements = widget.fraisScolaires
        .getAutresFraisPaiementsForYear()
        .where((p) => p.autreFraisId == selectedFrais!.id);
    for (final p in paiements) {
      Eleve? eleve;
      for (final e in widget.fraisScolaires.currentData.eleves) {
        if (e.id == p.eleveId) {
          eleve = e;
          break;
        }
      }
      final label = eleve != null ? eleve.section : "Élève(s) introuvable(s)";
      totals[label] = (totals[label] ?? 0) + p.montant;
    }
    return totals;
  }

  List<MapEntry<String, double>> _sortedEntries(Map<String, double> map) {
    final entries = map.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  void _showTotalsDialog() {
    if (selectedFrais == null) return;
    final frais = selectedFrais!;
    final byClasse = _sortedEntries(_totalsByClasseForSelected());
    final byOption = _sortedEntries(_totalsByOptionForSelected());
    final totalGeneral = byClasse.fold<double>(
        0.0, (sum, e) => sum + e.value);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Totaux — ${frais.nom}"),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Total général : ${totalGeneral.toStringAsFixed(0)} FC",
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Par option",
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo),
                ),
                const SizedBox(height: 6),
                if (byOption.isEmpty)
                  const Text("Aucun paiement enregistré pour ce frais.",
                      style: TextStyle(fontSize: 12, color: Colors.grey))
                else
                  ...byOption.map(
                        (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(e.key)),
                          Text(
                            "${e.value.toStringAsFixed(0)} FC",
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                const Text(
                  "Par classe",
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo),
                ),
                const SizedBox(height: 6),
                if (byClasse.isEmpty)
                  const Text("Aucun paiement enregistré pour ce frais.",
                      style: TextStyle(fontSize: 12, color: Colors.grey))
                else
                  ...byClasse.map(
                        (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(e.key)),
                          Text(
                            "${e.value.toStringAsFixed(0)} FC",
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Fermer"),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // ⚡ NOUVEAU — ADMINISTRATIONS & RÉPARTITION POUR LES "AUTRES FRAIS"
  // ==========================================================================
  // Demande de la direction : pouvoir AJOUTER, MODIFIER et SUPPRIMER des
  // administrations (nom + pourcentage) DIRECTEMENT depuis cet écran
  // "Autres Frais de Paiement" — sans jamais avoir besoin d'aller dans
  // Paramètres — et voir, pour le frais additionnel sélectionné, combien
  // chaque administration reçoit en % et en FC. Exactement le même
  // fonctionnement que pour les frais principaux, mais entièrement séparé.
  //
  // ⚡ NOUVEAU — cette répartition respecte désormais les filtres
  // Section/Classe actifs dans cet écran (`filterSection` / `filterClasse`).
  // Sans filtre, elle couvre TOUJOURS l'argent collecté pour ce frais dans
  // TOUTE l'école (comportement historique inchangé) — un seul frais, une
  // seule liste d'administrations, une seule répartition globale, quel que
  // soit le nombre de montants différents définis par section/classe.
  //
  // ⚠️⚠️⚠️ SÉPARATION TOTALE ET DÉFINITIVE AVEC LES FRAIS PRINCIPAUX ⚠️⚠️⚠️
  // Tout ce bloc utilise EXCLUSIVEMENT les méthodes dédiées côté
  // FraisScolaires : `getAutresFraisAdministrations`,
  // `addAutreFraisAdministration`, `updateAutreFraisAdministration`,
  // `deleteAutreFraisAdministration`, `getTotalPaidForAutreFrais` et
  // `getAdminDistributionForAutreFrais`. Aucune de ces méthodes ne touche à
  // `config.administrations` ni à `eleve.paid` — c'est-à-dire qu'AUCUNE
  // information saisie ici ne peut jamais apparaître dans la page de
  // "Répartition par Administration" des frais PRINCIPAUX, et
  // inversement les administrations des frais principaux n'apparaissent
  // JAMAIS ici. Les deux listes, les deux calculs et les deux écrans de
  // gestion restent strictement indépendants, comme demandé, pour ne
  // jamais créer de confusion ni de risque de calcul erroné entre écoles.
  //
  // Si aucune administration n'a encore été ajoutée pour les Autres Frais,
  // l'écran continue de fonctionner normalement : le paiement des frais,
  // les reçus et les totaux restent inchangés — seul un message invite à
  // en ajouter une si l'utilisateur le souhaite.
  // ==========================================================================
  void _showAdminRepartitionDialog() {
    if (selectedFrais == null) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final frais = selectedFrais!;
          final double total = widget.fraisScolaires.getTotalPaidForAutreFrais(
            frais,
            sectionFilter: filterSection,
            classFilter: filterClasse,
          );
          final Map<String, double> distribution = widget.fraisScolaires
              .getAdminDistributionForAutreFrais(
            frais,
            sectionFilter: filterSection,
            classFilter: filterClasse,
          );
          final administrations =
          widget.fraisScolaires.getAutresFraisAdministrations();

          final String filtreLabel = (filterSection == null &&
              filterClasse == null)
              ? "Toute l'école"
              : [
            if (filterSection != null) "Section : $filterSection",
            if (filterClasse != null) "Classe : $filterClasse",
          ].join(' — ');

          Future<void> refreshAndRebuild() async {
            setDialogState(() {});
            if (mounted) setState(() {});
          }

          void showAddOrEditAdminDialog({
            String? idToEdit,
            String initialNom = '',
            double? initialPourcentage,
          }) {
            final nomCtrl = TextEditingController(text: initialNom);
            final pourcentageCtrl = TextEditingController(
              text: initialPourcentage != null
                  ? initialPourcentage.toString()
                  : '',
            );
            final isEditing = idToEdit != null;

            showDialog(
              context: ctx,
              builder: (ctx2) => AlertDialog(
                title: Text(isEditing
                    ? "Modifier l'administration"
                    : "Nouvelle Administration (Autres Frais)"),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nomCtrl,
                      decoration: const InputDecoration(
                        labelText: "Nom de l'administration",
                        hintText: "Ex: Direction Provinciale",
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pourcentageCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Pourcentage (%)",
                        hintText: "Ex: 10",
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx2),
                    child: const Text("Annuler"),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final nom = nomCtrl.text.trim();
                      final pourcentage =
                      double.tryParse(pourcentageCtrl.text.trim());
                      if (nom.isEmpty ||
                          pourcentage == null ||
                          pourcentage < 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                "Veuillez entrer un nom et un pourcentage valides"),
                          ),
                        );
                        return;
                      }
                      if (isEditing) {
                        await widget.fraisScolaires
                            .updateAutreFraisAdministration(
                          idToEdit,
                          nom: nom,
                          pourcentage: pourcentage,
                        );
                      } else {
                        await widget.fraisScolaires
                            .addAutreFraisAdministration(
                          nom: nom,
                          pourcentage: pourcentage,
                        );
                      }
                      if (ctx2.mounted) Navigator.pop(ctx2);
                      await refreshAndRebuild();
                    },
                    child: const Text("Enregistrer"),
                  ),
                ],
              ),
            );
          }

          void confirmDeleteAdmin(String id, String nom) {
            showDialog(
              context: ctx,
              builder: (ctx2) => AlertDialog(
                title: const Text("Supprimer cette administration ?"),
                content: Text(
                  "Voulez-vous vraiment supprimer \"$nom\" de la liste des "
                      "administrations des Autres Frais ?",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx2),
                    child: const Text("Annuler"),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white),
                    onPressed: () async {
                      await widget.fraisScolaires
                          .deleteAutreFraisAdministration(id);
                      if (ctx2.mounted) Navigator.pop(ctx2);
                      await refreshAndRebuild();
                    },
                    child: const Text("Supprimer"),
                  ),
                ],
              ),
            );
          }

          return AlertDialog(
            title: Text("Administrations — ${frais.nom}"),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "Filtre actif : $filtreLabel",
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Total Collecté (\"${frais.nom}\") : "
                          "${total.toStringAsFixed(0)} FC",
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Ce montant ne comprend QUE les paiements de ce frais "
                          "additionnel — il n'inclut jamais les frais "
                          "mensuels principaux, et ces administrations "
                          "n'affectent jamais la répartition des frais "
                          "principaux.",
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Administrations (Autres Frais)",
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo),
                        ),
                        TextButton.icon(
                          onPressed: () => showAddOrEditAdminDialog(),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text("Ajouter",
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (administrations.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          "Aucune administration ajoutée pour le moment. "
                              "Utilisez le bouton \"Ajouter\" ci-dessus pour "
                              "en créer une (nom + pourcentage). Tant "
                              "qu'aucune n'est ajoutée, le paiement des "
                              "Autres Frais continue de fonctionner "
                              "normalement.",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      )
                    else
                      ...administrations.map((admin) {
                        final montant = distribution[admin.nom] ?? 0.0;
                        return Padding(
                          padding:
                          const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "${admin.nom} "
                                          "(${admin.pourcentage.toStringAsFixed(0)}%)",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500),
                                    ),
                                    Text(
                                      "${montant.toStringAsFixed(0)} FC",
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.indigo,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit,
                                    size: 18, color: Colors.indigo),
                                tooltip: "Modifier",
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 32, minHeight: 32),
                                onPressed: () => showAddOrEditAdminDialog(
                                  idToEdit: admin.id,
                                  initialNom: admin.nom,
                                  initialPourcentage: admin.pourcentage,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: Colors.red),
                                tooltip: "Supprimer",
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 32, minHeight: 32),
                                onPressed: () => confirmDeleteAdmin(
                                    admin.id, admin.nom),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Fermer"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fraisList = widget.fraisScolaires.getAutresFrais();

    // ⚡ NOUVEAU — options de classe pour le filtre, dépendantes de la
    // section choisie (utilise les classes AVEC sous-classe, comme
    // affichées pour chaque élève, pour que le filtre corresponde
    // exactement à `eleve.classe`).
    final classesOptionsForFilter = filterSection != null
        ? widget.fraisScolaires.getAllDisplayClassesForSection(filterSection!)
        : <String>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Autres Frais de Paiement"),
        actions: [
          // ⚡ CORRIGÉ — le bouton "Réimprimer un reçu" a été retiré (sur
          // demande de la direction) ; le bouton des totaux reste.
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: "Totaux par classe et par option",
            onPressed: selectedFrais == null ? null : _showTotalsDialog,
          ),
          // ⚡ NOUVEAU — accès rapide, depuis l'AppBar, à la gestion des
          // administrations (ajout/modification/suppression) et à la
          // répartition en % pour le frais actuellement sélectionné (et
          // le filtre section/classe actif, s'il y en a un).
          IconButton(
            icon: const Icon(Icons.account_balance),
            tooltip: "Administrations (Autres Frais)",
            onPressed:
            selectedFrais == null ? null : _showAdminRepartitionDialog,
          ),
        ],
      ),
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
                  items: fraisList.map((f) {
                    final hasExceptions = f.montantsParSection.isNotEmpty ||
                        f.montantsParClasse.isNotEmpty;
                    return DropdownMenuItem(
                      value: f,
                      child: Text(
                          "${f.nom} — ${f.montant.toStringAsFixed(0)} FC (${_scopeLabel(f)})"
                              "${hasExceptions ? ' • montants variables' : ''}"),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedFrais = value;
                      selectedStudentIds.clear();
                      // ⚡ NOUVEAU — on réinitialise les filtres quand on
                      // change de type de frais, pour éviter un filtre
                      // hérité qui ne correspondrait plus au nouveau frais.
                      filterSection = null;
                      filterClasse  = null;
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
                // ⚡ NOUVEAU — filtres optionnels Section / Classe, pour
                // naviguer facilement même sur un frais "toute l'école".
                if (selectedFrais != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: filterSection,
                          hint: const Text("Toutes les sections"),
                          items: [
                            const DropdownMenuItem<String>(
                                value: null,
                                child: Text("Toutes les sections")),
                            ...widget.fraisScolaires.config.sections.map(
                                    (s) => DropdownMenuItem(
                                    value: s, child: Text(s))),
                          ],
                          onChanged: (v) => setState(() {
                            filterSection = v;
                            filterClasse  = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: filterClasse,
                          hint: const Text("Toutes les classes"),
                          items: [
                            const DropdownMenuItem<String>(
                                value: null,
                                child: Text("Toutes les classes")),
                            ...classesOptionsForFilter.map(
                                    (c) => DropdownMenuItem(
                                    value: c, child: Text(c))),
                          ],
                          onChanged: filterSection == null
                              ? null
                              : (v) => setState(() => filterClasse = v),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // ⚡ NOUVEAU — dès qu'un frais est sélectionné, le bouton de
          // répartition par administration apparaît EN HAUT de la liste
          // des élèves, juste à côté du bouton "Voir les totaux" déjà
          // existant (regroupés dans un Wrap pour rester lisibles même
          // sur un écran étroit).
          if (selectedFrais != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${_eligibleFiltered.length} élève(s) concerné(s) — cochez "
                        "ceux qui payent, ou utilisez le bouton paiement direct.",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: _showTotalsDialog,
                        icon: const Icon(Icons.bar_chart, size: 18),
                        label: const Text("Voir les totaux",
                            style: TextStyle(fontSize: 12)),
                      ),
                      TextButton.icon(
                        onPressed: _showAdminRepartitionDialog,
                        icon: const Icon(Icons.account_balance, size: 18),
                        label: const Text(
                            "Administrations & Répartition",
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
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
                  // ⚡ NOUVEAU — montant réellement dû par CET élève
                  // (dépend de ses éventuelles exceptions par
                  // section/classe pour ce frais).
                  final double montantEleve = widget.fraisScolaires
                      .getMontantAutreFraisPourEleve(selectedFrais!, eleve);
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
                        'ID: ${eleve.id} | Classe: ${eleve.classe} (${eleve.section}) | '
                            'Montant: ${montantEleve.toStringAsFixed(0)} FC',
                      ),
                      // ⚡ CORRIGÉ — le bouton de réimpression manuelle a
                      // été retiré ; un élève déjà payé n'affiche plus
                      // qu'un simple statut "Payé".
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