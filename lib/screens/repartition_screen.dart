import 'dart:collection';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../frais_scolaires.dart';
import '../app_state.dart';
import '../models.dart';

class RepartitionScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const RepartitionScreen({super.key, required this.fraisScolaires});

  @override
  State<RepartitionScreen> createState() => _RepartitionScreenState();
}

class _RepartitionScreenState extends State<RepartitionScreen> {
  FraisScolaires get fraisScolaires => widget.fraisScolaires;

  String _periodeGlobale = 'year';

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

  String _labelPortee(String portee) {
    switch (portee) {
      case kDepenseIndependante:
        return "Indépendante";
      case kDepenseMixte:
        return "Mixte";
      case kDepenseGlobale:
      default:
        return "Globale";
    }
  }

  Color _couleurPortee(String portee) {
    switch (portee) {
      case kDepenseIndependante:
        return Colors.deepOrange;
      case kDepenseMixte:
        return Colors.purple;
      case kDepenseGlobale:
      default:
        return Colors.red.shade700;
    }
  }

  String _formatDateCourte(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(d.day)}/${two(d.month)}/${d.year}";
  }

  Future<void> _startAddDepense() async {
    if (!await _verifyBackupPassword()) return;
    await _openAddDepenseDialog();
  }

  Future<void> _openAddDepenseDialog() async {
    final motifController = TextEditingController();
    final montantController = TextEditingController();

    String portee = kDepenseGlobale;
    String? sectionIndep;
    final Set<String> sectionsMixte = {};
    final Set<String> classesSel = {};
    String? rubrique;
    DateTime? dateSelectionnee;
    // ⚡ NOUVEAU — mois scolaire d'imputation (Septembre à Juin), pré-rempli
    // selon la date, modifiable manuellement par l'utilisateur.
    String? moisImputation =
        fraisScolaires.schoolMonthNameForDate(DateTime.now());
    bool moisImputationModifieManuellement = false;

    final sectionsDisponibles = fraisScolaires.config.sections;
    final rubriquesDisponibles = fraisScolaires.getRubriquesDisponibles();

    List<String> sectionsChoisies() {
      if (portee == kDepenseIndependante) {
        final s = sectionIndep;
        return s == null ? <String>[] : <String>[s];
      }
      if (portee == kDepenseMixte) return sectionsMixte.toList();
      return <String>[];
    }

    List<String> classesProposees() {
      final result = <String>[];
      for (final s in sectionsChoisies()) {
        for (final c in fraisScolaires.getAllDisplayClassesForSection(s)) {
          if (!result.contains(c)) result.add(c);
        }
      }
      return result;
    }

    double? soldeDisponible() {
      final r = rubrique;
      if (r == null) return null;
      final secs = sectionsChoisies();
      if (portee != kDepenseGlobale && secs.isEmpty) return null;
      return fraisScolaires.getSoldeDisponibleRubrique(
        rubrique: r,
        portee: portee,
        sections: secs,
      );
    }

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final secs = sectionsChoisies();
            final classesOptions = classesProposees();
            final solde = soldeDisponible();

            final int numeroDate = portee == kDepenseGlobale ? 4 : 5;

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.money_off, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(child: Text("Nouvelle Dépense")),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("1. Type de dépense",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ChoiceChip(
                            label: const Text("Globale (toute l'école)"),
                            selected: portee == kDepenseGlobale,
                            selectedColor: Colors.red.shade100,
                            onSelected: (_) => setDialogState(() {
                              portee = kDepenseGlobale;
                              classesSel.clear();
                            }),
                          ),
                          ChoiceChip(
                            label: const Text("Indépendante (1 section)"),
                            selected: portee == kDepenseIndependante,
                            selectedColor: Colors.deepOrange.shade100,
                            onSelected: (_) => setDialogState(() {
                              portee = kDepenseIndependante;
                              classesSel.clear();
                            }),
                          ),
                          ChoiceChip(
                            label: const Text("Mixte (2 sections ou plus)"),
                            selected: portee == kDepenseMixte,
                            selectedColor: Colors.purple.shade100,
                            onSelected: (_) => setDialogState(() {
                              portee = kDepenseMixte;
                              classesSel.clear();
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        portee == kDepenseGlobale
                            ? "Concerne toute l'école."
                            : portee == kDepenseIndependante
                            ? "Concerne une seule section."
                            : "Concerne plusieurs sections : le montant sera "
                            "réparti à parts égales entre elles.",
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black54),
                      ),

                      if (portee == kDepenseIndependante) ...[
                        const SizedBox(height: 14),
                        const Text("2. Section concernée",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          value: sectionIndep,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: "Choisir la section",
                            border: OutlineInputBorder(),
                          ),
                          items: sectionsDisponibles
                              .map((s) =>
                              DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (v) => setDialogState(() {
                            sectionIndep = v;
                            classesSel.clear();
                          }),
                        ),
                      ],
                      if (portee == kDepenseMixte) ...[
                        const SizedBox(height: 14),
                        const Text("2. Sections concernées (2 ou plus)",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: sectionsDisponibles.map((s) {
                            final sel = sectionsMixte.contains(s);
                            return FilterChip(
                              label: Text(s),
                              selected: sel,
                              selectedColor: Colors.purple.shade100,
                              onSelected: (v) => setDialogState(() {
                                if (v) {
                                  sectionsMixte.add(s);
                                } else {
                                  sectionsMixte.remove(s);
                                }
                                classesSel.clear();
                              }),
                            );
                          }).toList(),
                        ),
                      ],

                      if (portee != kDepenseGlobale &&
                          classesOptions.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Text("Classes concernées (facultatif)",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(
                          classesSel.isEmpty
                              ? "Aucune sélection = toutes les classes."
                              : "${classesSel.length} classe(s) choisie(s).",
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: classesOptions.map((c) {
                            final sel = classesSel.contains(c);
                            return FilterChip(
                              label: Text(c),
                              selected: sel,
                              onSelected: (v) => setDialogState(() {
                                if (v) {
                                  classesSel.add(c);
                                } else {
                                  classesSel.remove(c);
                                }
                              }),
                            );
                          }).toList(),
                        ),
                      ],

                      const SizedBox(height: 14),
                      Text(
                          portee == kDepenseGlobale
                              ? "2. Rubrique (administration)"
                              : "3. Rubrique (administration)",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: rubrique,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Sortir l'argent de la rubrique",
                          border: OutlineInputBorder(),
                        ),
                        items: rubriquesDisponibles
                            .map((r) =>
                            DropdownMenuItem(value: r, child: Text(r)))
                            .toList(),
                        onChanged: (v) => setDialogState(() => rubrique = v),
                      ),
                      if (fraisScolaires.config.administrations.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            "Aucune administration configurée dans les "
                                "Paramètres : seule la rubrique « Autre » est "
                                "disponible.",
                            style: TextStyle(
                                fontSize: 11, color: Colors.orange),
                          ),
                        ),
                      if (solde != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: solde >= 0
                                ? Colors.green.withAlpha(25)
                                : Colors.red.withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            "Solde disponible sur cette rubrique : "
                                "${formatMontant(solde)} FC",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: solde >= 0
                                  ? Colors.green.shade800
                                  : Colors.red.shade800,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 14),
                      Text(
                          portee == kDepenseGlobale
                              ? "3. Motif et montant"
                              : "4. Motif et montant",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: motifController,
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: "Motif / Justification",
                          hintText:
                          "Ex: Achat de craies, réparation, transport...",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: montantController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: "Montant à faire sortir (FC)",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                      ),
                      if (secs.isNotEmpty && portee != kDepenseGlobale) ...[
                        const SizedBox(height: 8),
                        Text(
                          "Imputée à : ${secs.join(', ')}"
                              "${classesSel.isNotEmpty ? ' — ${classesSel.join(', ')}' : ''}",
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54),
                        ),
                      ],

                      const SizedBox(height: 14),
                      Text(
                        "$numeroDate. Date (facultatif)",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Laissez vide pour utiliser la date d'aujourd'hui. "
                            "Utile si vous enregistrez maintenant une "
                            "dépense faite un autre jour (par ex. hier).",
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: dateSelectionnee ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate:
                            DateTime.now().add(const Duration(days: 365)),
                            helpText: "Choisir la date de la dépense",
                            cancelText: "Annuler",
                            confirmText: "Valider",
                          );
                          if (picked != null) {
                            setDialogState(() {
                              dateSelectionnee = picked;
                              if (!moisImputationModifieManuellement) {
                                moisImputation = fraisScolaires
                                    .schoolMonthNameForDate(picked);
                              }
                            });
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today,
                                  size: 18, color: Colors.indigo),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  dateSelectionnee == null
                                      ? "Aujourd'hui (par défaut)"
                                      : _formatDateCourte(dateSelectionnee!),
                                  style: TextStyle(
                                    color: dateSelectionnee == null
                                        ? Colors.black54
                                        : Colors.black87,
                                    fontWeight: dateSelectionnee == null
                                        ? FontWeight.normal
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (dateSelectionnee != null)
                                InkWell(
                                  onTap: () => setDialogState(
                                          () => dateSelectionnee = null),
                                  child: const Padding(
                                    padding: EdgeInsets.all(2),
                                    child: Icon(Icons.close,
                                        size: 18, color: Colors.grey),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),
                      Text(
                        "${numeroDate + 1}. Mois d'imputation (pour les rapports)",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Mois scolaire dans lequel cette dépense doit "
                            "apparaître (rapport mensuel, statistiques). "
                            "Pré-rempli selon la date ci-dessus ; "
                            "modifiable si la dépense concerne un autre mois.",
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: moisImputation,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Mois d'imputation",
                          border: OutlineInputBorder(),
                        ),
                        items: fraisScolaires.months
                            .map((m) =>
                            DropdownMenuItem(value: m, child: Text(m)))
                            .toList(),
                        onChanged: (v) => setDialogState(() {
                          moisImputation = v;
                          moisImputationModifieManuellement = true;
                        }),
                      ),
                    ],
                  ),
                ),
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
                    final r = rubrique;
                    final sectionsFinales = sectionsChoisies();

                    void erreur(String message) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text(message)),
                      );
                    }

                    if (portee == kDepenseIndependante &&
                        sectionsFinales.isEmpty) {
                      erreur("Veuillez choisir la section concernée.");
                      return;
                    }
                    if (portee == kDepenseMixte && sectionsFinales.length < 2) {
                      erreur("Une dépense mixte doit concerner au moins "
                          "deux sections.");
                      return;
                    }
                    if (r == null) {
                      erreur("Veuillez choisir la rubrique.");
                      return;
                    }
                    if (motif.isEmpty) {
                      erreur("Veuillez indiquer un motif.");
                      return;
                    }
                    if (montant == null || montant <= 0) {
                      erreur("Montant invalide.");
                      return;
                    }

                    final soldeActuel = soldeDisponible();
                    if (soldeActuel != null && montant > soldeActuel) {
                      final continuer = await showDialog<bool>(
                        context: dialogContext,
                        builder: (ctx) => AlertDialog(
                          title: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.orange),
                              SizedBox(width: 8),
                              Expanded(child: Text("Solde insuffisant")),
                            ],
                          ),
                          content: Text(
                            "Le solde disponible sur la rubrique « $r » est de "
                                "${formatMontant(soldeActuel)} FC, mais vous "
                                "voulez sortir ${formatMontant(montant)} FC.\n\n"
                                "Le reste deviendra négatif. Continuer quand même ?",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text("Annuler"),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text("Continuer"),
                            ),
                          ],
                        ),
                      );
                      if (continuer != true) return;
                    }

                    await fraisScolaires.addDepense(
                      motif: motif,
                      montant: montant,
                      portee: portee,
                      sections: sectionsFinales,
                      classes: classesSel.toList(),
                      rubrique: r,
                      date: dateSelectionnee,
                      moisImputation: moisImputation,
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

  Future<bool> _confirmDeleteDepense(Depense depense) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer cette dépense ?"),
        content: Text(
          "${depense.motif}\n"
              "${formatMontant(depense.montant)} FC — ${depense.dateFormatee}\n"
              "Type : ${depense.porteeLabel} | ${depense.sectionsLabel}\n"
              "Rubrique : ${depense.rubriqueAffichee}",
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

  Future<bool> _editDepenseDate(Depense depense) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: depense.date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: "Choisir la date réelle de cette dépense",
      cancelText: "Annuler",
      confirmText: "Valider",
    );
    if (picked == null) return false;

    final newDate = DateTime(
      picked.year,
      picked.month,
      picked.day,
      depense.date.hour,
      depense.date.minute,
    );

    if (!await _verifyBackupPassword()) return false;
    await fraisScolaires.updateDepenseDate(depense.id, newDate);
    return true;
  }

  // ⚡ NOUVEAU — modifier le mois scolaire d'imputation d'une dépense déjà
  // enregistrée (rapport mensuel, statistiques).
  Future<bool> _editDepenseMois(Depense depense) async {
    String? moisChoisi = depense.moisImputation;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text("Mois d'imputation"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Mois scolaire dans lequel cette dépense doit apparaître "
                    "dans les rapports mensuels. Choisissez \"Selon la date\" "
                    "pour revenir au comportement par défaut.",
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                value: moisChoisi,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: "Mois d'imputation",
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text("Selon la date de la dépense"),
                  ),
                  ...fraisScolaires.months.map((m) =>
                      DropdownMenuItem<String?>(value: m, child: Text(m))),
                ],
                onChanged: (v) => setDialogState(() => moisChoisi = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Valider"),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return false;
    if (!await _verifyBackupPassword()) return false;
    await fraisScolaires.updateDepenseMoisImputation(depense.id, moisChoisi);
    return true;
  }

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
              "enregistrées pour l'année ${fraisScolaires.currentYear} "
              "(tous types confondus).\n\n"
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

  void _openHistoriqueDialog() {
    String filtre = 'all';
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final toutes = fraisScolaires.getDepensesForYear();
            final depenses = filtre == 'all'
                ? toutes
                : toutes.where((d) => d.portee == filtre).toList();
            final totalAffiche =
            depenses.fold(0.0, (sum, d) => sum + d.montant);

            Widget filtreChip(String value, String label) {
              return ChoiceChip(
                label: Text(label, style: const TextStyle(fontSize: 11)),
                selected: filtre == value,
                selectedColor: Colors.indigo.shade100,
                onSelected: (_) => setDialogState(() => filtre = value),
              );
            }

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.history, color: Colors.indigo),
                  SizedBox(width: 8),
                  Expanded(child: Text("Historique des Dépenses")),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        filtreChip('all', "Toutes"),
                        filtreChip(kDepenseGlobale, "Globales"),
                        filtreChip(kDepenseIndependante, "Indépendantes"),
                        filtreChip(kDepenseMixte, "Mixtes"),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        "Total affiché : ${formatMontant(totalAffiche)} FC",
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Divider(height: 10),
                    Flexible(
                      child: depenses.isEmpty
                          ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          "Aucune dépense enregistrée pour ce filtre.",
                          textAlign: TextAlign.center,
                        ),
                      )
                          : ListView.separated(
                        shrinkWrap: true,
                        itemCount: depenses.length,
                        separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final d = depenses[index];
                          final couleur = _couleurPortee(d.portee);
                          return ListTile(
                            dense: true,
                            isThreeLine: true,
                            leading: Icon(Icons.remove_circle,
                                color: couleur),
                            title: Text(d.motif),
                            subtitle: Text(
                              "${d.porteeLabel} — ${d.sectionsLabel}\n"
                                  "Rubrique : ${d.rubriqueAffichee}"
                                  "${d.portee != kDepenseGlobale && d.classes.isNotEmpty ? '\nClasses : ${d.classes.join(', ')}' : ''}\n"
                                  "${d.dateFormatee}"
                                  "${d.moisImputation != null && d.moisImputation!.trim().isNotEmpty ? ' — Imputée à : ${d.moisImputation}' : ''}",
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Column(
                              mainAxisAlignment:
                              MainAxisAlignment.center,
                              crossAxisAlignment:
                              CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "-${formatMontant(d.montant)} FC",
                                  style: TextStyle(
                                      color: couleur,
                                      fontWeight: FontWeight.bold),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    InkWell(
                                      onTap: () async {
                                        final edited =
                                        await _editDepenseDate(d);
                                        if (edited) {
                                          setDialogState(() {});
                                        }
                                      },
                                      child: const Padding(
                                        padding:
                                        EdgeInsets.only(top: 4, right: 10),
                                        child: Icon(Icons.edit_calendar,
                                            size: 18, color: Colors.indigo),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () async {
                                        final edited =
                                        await _editDepenseMois(d);
                                        if (edited) {
                                          setDialogState(() {});
                                        }
                                      },
                                      child: const Padding(
                                        padding:
                                        EdgeInsets.only(top: 4, right: 10),
                                        child: Icon(Icons.event_note,
                                            size: 18, color: Colors.teal),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () async {
                                        final deleted =
                                        await _confirmDeleteDepense(d);
                                        if (deleted) {
                                          setDialogState(() {});
                                        }
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.only(top: 4),
                                        child: Icon(Icons.delete_outline,
                                            size: 18, color: Colors.grey),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (toutes.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    label: const Text("Tout effacer",
                        style: TextStyle(color: Colors.red)),
                    onPressed: () async {
                      final cleared =
                      await _confirmClearAllDepenses(toutes.length);
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

  // ⚡ NOUVEAU — rapport PDF contenant uniquement la partie dépenses, pour
  // une période choisie par l'utilisateur.
  Future<void> _openRapportDepensesDialog() async {
    String periode = 'month';
    String moisChoisi =
        fraisScolaires.currentSchoolMonthName ?? fraisScolaires.months.first;
    String? sectionChoisie;
    final cityController = TextEditingController(
        text: fraisScolaires.lastReportCity ?? 'Lubumbashi');
    bool generating = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.picture_as_pdf, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(child: Text("Rapport des Dépenses")),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("1. Période",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ChoiceChip(
                            label: const Text("Aujourd'hui"),
                            selected: periode == 'today',
                            onSelected: (_) =>
                                setDialogState(() => periode = 'today'),
                          ),
                          ChoiceChip(
                            label: const Text("Un mois"),
                            selected: periode == 'month',
                            onSelected: (_) =>
                                setDialogState(() => periode = 'month'),
                          ),
                          ChoiceChip(
                            label: const Text("Toute l'année"),
                            selected: periode == 'year',
                            onSelected: (_) =>
                                setDialogState(() => periode = 'year'),
                          ),
                        ],
                      ),
                      if (periode == 'month') ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: moisChoisi,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: "Mois scolaire",
                            border: OutlineInputBorder(),
                          ),
                          items: fraisScolaires.months
                              .map((m) =>
                              DropdownMenuItem(value: m, child: Text(m)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setDialogState(() => moisChoisi = v);
                            }
                          },
                        ),
                      ],
                      const SizedBox(height: 14),
                      const Text("2. Section (facultatif)",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String?>(
                        value: sectionChoisie,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Section",
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text("Toute l'école"),
                          ),
                          ...fraisScolaires.config.sections.map((s) =>
                              DropdownMenuItem<String?>(
                                  value: s, child: Text(s))),
                        ],
                        onChanged: (v) =>
                            setDialogState(() => sectionChoisie = v),
                      ),
                      const SizedBox(height: 14),
                      const Text("3. Ville (« Fait à ... »)",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: cityController,
                        decoration: const InputDecoration(
                          labelText: "Ville",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: generating
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text("Annuler"),
                ),
                ElevatedButton.icon(
                  icon: generating
                      ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.picture_as_pdf),
                  label: Text(generating ? "Génération..." : "Générer"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: generating
                      ? null
                      : () async {
                    setDialogState(() => generating = true);

                    final city = cityController.text.trim();
                    await fraisScolaires.setLastReportCity(city);

                    final String dateJour =
                    DateTime.now().toString().split(' ')[0];
                    final String suffixeMois =
                    periode == 'month' ? "_$moisChoisi" : "";
                    final filename =
                        "Rapport_Depenses_$periode$suffixeMois"
                        "_$dateJour";

                    final result =
                    await fraisScolaires.generateDepensesOnlyPdf(
                      filename: filename,
                      period: periode,
                      mois: periode == 'month' ? moisChoisi : null,
                      sectionFilter: sectionChoisie,
                      city: city.isEmpty ? null : city,
                    );

                    if (!dialogContext.mounted) return;
                    setDialogState(() => generating = false);

                    if (result['empty'] == true) {
                      Navigator.pop(dialogContext);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              "Aucune dépense enregistrée pour cette "
                                  "période."),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(dialogContext);
                    if (!mounted) return;
                    if (result['success'] == true) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              "✅ Rapport des dépenses généré : "
                                  "${result['path']}"),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              "Erreur : ${result['error'] ?? 'inconnue'}"),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================================================
  // ⚡ NOUVEAU — ENTRÉES D'ARGENT (apports de caisse)
  // ==========================================================================

  String _labelTypeEntree(String type) {
    switch (type) {
      case kEntreeRetourReliquat:
        return 'Retour de reliquat';
      case kEntreeSubvention:
        return 'Subvention';
      case kEntreeAutre:
        return 'Autre apport';
      case kEntreeDon:
      default:
        return 'Don';
    }
  }

  Future<void> _startAddEntree() async {
    if (!await _verifyBackupPassword()) return;
    await _openAddEntreeDialog();
  }

  Future<void> _openAddEntreeDialog() async {
    final justificationController = TextEditingController();
    final motifController = TextEditingController();
    final montantController = TextEditingController();

    String type = kEntreeDon;
    String portee = kDepenseGlobale;
    String? sectionIndep;
    final Set<String> sectionsMixte = {};
    String? rubrique;
    DateTime? dateSelectionnee;
    String? moisImputation =
        fraisScolaires.schoolMonthNameForDate(DateTime.now());
    bool moisImputationModifieManuellement = false;
    String? depenseLieeId;

    final sectionsDisponibles = fraisScolaires.config.sections;
    final rubriquesDisponibles = fraisScolaires.getRubriquesDisponibles();
    final depensesDisponibles = fraisScolaires.getDepensesForYear();

    List<String> sectionsChoisies() {
      if (portee == kDepenseIndependante) {
        final s = sectionIndep;
        return s == null ? <String>[] : <String>[s];
      }
      if (portee == kDepenseMixte) return sectionsMixte.toList();
      return <String>[];
    }

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Depense? depenseChoisie;
            if (depenseLieeId != null) {
              for (final d in depensesDisponibles) {
                if (d.id == depenseLieeId) {
                  depenseChoisie = d;
                  break;
                }
              }
            }
            final double dejaRetourne = depenseLieeId != null
                ? fraisScolaires.totalEntreesRetourPourDepense(depenseLieeId!)
                : 0.0;
            final double? reliquatDisponible = depenseChoisie != null
                ? depenseChoisie.montant - dejaRetourne
                : null;

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.add_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(child: Text("Entrer de l'argent")),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Type d'entrée",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ChoiceChip(
                            label: const Text("Retour de reliquat"),
                            selected: type == kEntreeRetourReliquat,
                            selectedColor: Colors.teal.shade100,
                            onSelected: (_) => setDialogState(() {
                              type = kEntreeRetourReliquat;
                            }),
                          ),
                          ChoiceChip(
                            label: const Text("Don"),
                            selected: type == kEntreeDon,
                            selectedColor: Colors.green.shade100,
                            onSelected: (_) => setDialogState(() {
                              type = kEntreeDon;
                              depenseLieeId = null;
                            }),
                          ),
                          ChoiceChip(
                            label: const Text("Subvention"),
                            selected: type == kEntreeSubvention,
                            selectedColor: Colors.blue.shade100,
                            onSelected: (_) => setDialogState(() {
                              type = kEntreeSubvention;
                              depenseLieeId = null;
                            }),
                          ),
                          ChoiceChip(
                            label: const Text("Autre apport"),
                            selected: type == kEntreeAutre,
                            selectedColor: Colors.grey.shade300,
                            onSelected: (_) => setDialogState(() {
                              type = kEntreeAutre;
                              depenseLieeId = null;
                            }),
                          ),
                        ],
                      ),

                      if (type == kEntreeRetourReliquat) ...[
                        const SizedBox(height: 14),
                        const Text("Dépense d'origine",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        if (depensesDisponibles.isEmpty)
                          const Text(
                            "Aucune dépense enregistrée cette année.",
                            style:
                            TextStyle(fontSize: 11, color: Colors.orange),
                          )
                        else
                          DropdownButtonFormField<String>(
                            value: depenseLieeId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: "Choisir la dépense",
                              border: OutlineInputBorder(),
                            ),
                            items: depensesDisponibles
                                .map((d) => DropdownMenuItem(
                              value: d.id,
                              child: Text(
                                "${d.dateFormatee} — ${d.motif} "
                                    "(${formatMontant(d.montant)} FC)",
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                                .toList(),
                            onChanged: (v) => setDialogState(() {
                              depenseLieeId = v;
                              if (v != null) {
                                for (final d in depensesDisponibles) {
                                  if (d.id == v) {
                                    if (d.rubrique.trim().isNotEmpty) {
                                      rubrique = d.rubrique;
                                    }
                                    break;
                                  }
                                }
                              }
                            }),
                          ),
                        if (reliquatDisponible != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.teal.withAlpha(25),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "Déjà retourné : ${formatMontant(dejaRetourne)} "
                                  "FC sur ${formatMontant(depenseChoisie!.montant)} "
                                  "FC — reliquat disponible : "
                                  "${formatMontant(reliquatDisponible)} FC",
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.teal),
                            ),
                          ),
                        ],
                      ],

                      const SizedBox(height: 14),
                      const Text("Portée",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ChoiceChip(
                            label: const Text("Globale (toute l'école)"),
                            selected: portee == kDepenseGlobale,
                            onSelected: (_) => setDialogState(() {
                              portee = kDepenseGlobale;
                            }),
                          ),
                          ChoiceChip(
                            label: const Text("Indépendante (1 section)"),
                            selected: portee == kDepenseIndependante,
                            onSelected: (_) => setDialogState(() {
                              portee = kDepenseIndependante;
                            }),
                          ),
                          ChoiceChip(
                            label: const Text("Mixte (2 sections ou plus)"),
                            selected: portee == kDepenseMixte,
                            onSelected: (_) => setDialogState(() {
                              portee = kDepenseMixte;
                            }),
                          ),
                        ],
                      ),
                      if (portee == kDepenseIndependante) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: sectionIndep,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: "Section concernée",
                            border: OutlineInputBorder(),
                          ),
                          items: sectionsDisponibles
                              .map((s) =>
                              DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => sectionIndep = v),
                        ),
                      ],
                      if (portee == kDepenseMixte) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: sectionsDisponibles.map((s) {
                            final sel = sectionsMixte.contains(s);
                            return FilterChip(
                              label: Text(s),
                              selected: sel,
                              onSelected: (v) => setDialogState(() {
                                if (v) {
                                  sectionsMixte.add(s);
                                } else {
                                  sectionsMixte.remove(s);
                                }
                              }),
                            );
                          }).toList(),
                        ),
                      ],

                      const SizedBox(height: 14),
                      const Text("Rubrique",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: rubrique,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Rubrique créditée",
                          border: OutlineInputBorder(),
                        ),
                        items: rubriquesDisponibles
                            .map((r) =>
                            DropdownMenuItem(value: r, child: Text(r)))
                            .toList(),
                        onChanged: (v) => setDialogState(() => rubrique = v),
                      ),

                      const SizedBox(height: 14),
                      const Text("Justification (obligatoire)",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: justificationController,
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText:
                          "Ex : reste non utilisé de la sortie scolaire "
                              "du 12/10, reçu de M. X...",
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 12),
                      const Text("Motif / nom court (facultatif)",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: motifController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 12),
                      TextField(
                        controller: montantController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: "Montant reçu (FC)",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                      ),

                      const SizedBox(height: 14),
                      const Text("Date (facultatif)",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: dateSelectionnee ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate:
                            DateTime.now().add(const Duration(days: 365)),
                            helpText: "Choisir la date de l'entrée",
                            cancelText: "Annuler",
                            confirmText: "Valider",
                          );
                          if (picked != null) {
                            setDialogState(() {
                              dateSelectionnee = picked;
                              if (!moisImputationModifieManuellement) {
                                moisImputation = fraisScolaires
                                    .schoolMonthNameForDate(picked);
                              }
                            });
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today,
                                  size: 18, color: Colors.indigo),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  dateSelectionnee == null
                                      ? "Aujourd'hui (par défaut)"
                                      : _formatDateCourte(dateSelectionnee!),
                                ),
                              ),
                              if (dateSelectionnee != null)
                                InkWell(
                                  onTap: () => setDialogState(
                                          () => dateSelectionnee = null),
                                  child: const Padding(
                                    padding: EdgeInsets.all(2),
                                    child: Icon(Icons.close,
                                        size: 18, color: Colors.grey),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),
                      const Text("Mois d'imputation (pour les rapports)",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: moisImputation,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Mois d'imputation",
                          border: OutlineInputBorder(),
                        ),
                        items: fraisScolaires.months
                            .map((m) =>
                            DropdownMenuItem(value: m, child: Text(m)))
                            .toList(),
                        onChanged: (v) => setDialogState(() {
                          moisImputation = v;
                          moisImputationModifieManuellement = true;
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Annuler"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final montantText =
                    montantController.text.trim().replaceAll(',', '.');
                    final montant = double.tryParse(montantText);
                    final sectionsFinales = sectionsChoisies();

                    void erreur(String message) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text(message)),
                      );
                    }

                    if (montant == null || montant <= 0) {
                      erreur("Montant invalide.");
                      return;
                    }
                    if (justificationController.text.trim().isEmpty) {
                      erreur("La justification est obligatoire.");
                      return;
                    }
                    if (rubrique == null) {
                      erreur("Veuillez choisir la rubrique.");
                      return;
                    }
                    if (portee == kDepenseIndependante &&
                        sectionsFinales.isEmpty) {
                      erreur("Veuillez choisir la section concernée.");
                      return;
                    }
                    if (portee == kDepenseMixte &&
                        sectionsFinales.length < 2) {
                      erreur("Une entrée mixte doit concerner au moins "
                          "deux sections.");
                      return;
                    }
                    if (type == kEntreeRetourReliquat &&
                        (depenseLieeId == null ||
                            depenseLieeId!.trim().isEmpty)) {
                      erreur("Veuillez choisir la dépense d'origine.");
                      return;
                    }

                    final messageErreur = await fraisScolaires.addEntree(
                      montant: montant,
                      type: type,
                      justification: justificationController.text,
                      motif: motifController.text,
                      rubrique: rubrique!,
                      portee: portee,
                      sections: sectionsFinales,
                      date: dateSelectionnee,
                      moisImputation: moisImputation,
                      depenseLieeId: depenseLieeId,
                    );

                    if (messageErreur != null) {
                      erreur(messageErreur);
                      return;
                    }

                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text("Enregistrer l'entrée"),
                ),
              ],
            );
          },
        );
      },
    );
    if (mounted) setState(() {});
  }

  Future<bool> _annulerEntreeDialog(Entree entree) async {
    final motifController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Annuler cette entrée ?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${entree.typeLabel} — ${formatMontant(entree.montant)} FC\n"
                  "Rubrique : ${entree.rubriqueAffichee}\n"
                  "${entree.justification}",
            ),
            const SizedBox(height: 12),
            const Text("Motif de l'annulation (obligatoire) :",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
            const SizedBox(height: 6),
            TextField(
              controller: motifController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: "Ex : erreur de saisie, doublon...",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Retour"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              if (motifController.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                      content:
                      Text("Le motif d'annulation est obligatoire.")),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text("Confirmer l'annulation"),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    if (!await _verifyBackupPassword()) return false;

    final erreur = await fraisScolaires.annulerEntree(
        entree.id, motifController.text);
    if (erreur != null) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erreur), backgroundColor: Colors.red),
      );
      return false;
    }
    return true;
  }

  void _openHistoriqueEntreesDialog() {
    String filtrePeriode = 'year';
    String? filtreRubrique;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final toutes = fraisScolaires.getEntreesForPeriod(filtrePeriode);
            final rubriquesPresentes = toutes
                .map((e) => e.rubriqueAffichee)
                .toSet()
                .toList()
              ..sort();
            final entrees = filtreRubrique == null
                ? toutes
                : toutes
                .where((e) => e.rubriqueAffichee == filtreRubrique)
                .toList();
            final double totalActif = entrees
                .where((e) => !e.annulee)
                .fold(0.0, (sum, e) => sum + e.montant);

            Widget filtreChip(String value, String label) {
              return ChoiceChip(
                label: Text(label, style: const TextStyle(fontSize: 11)),
                selected: filtrePeriode == value,
                selectedColor: Colors.green.shade100,
                onSelected: (_) =>
                    setDialogState(() => filtrePeriode = value),
              );
            }

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.history, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(child: Text("Historique des Entrées")),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        filtreChip('today', "Aujourd'hui"),
                        filtreChip('month', "Ce mois"),
                        filtreChip('year', "Cette année"),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      value: filtreRubrique,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: "Filtrer par rubrique",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text("Toutes les rubriques"),
                        ),
                        ...rubriquesPresentes.map((r) =>
                            DropdownMenuItem<String?>(
                                value: r, child: Text(r))),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => filtreRubrique = v),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        "Total actif affiché : ${formatMontant(totalActif)} FC",
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Divider(height: 10),
                    Flexible(
                      child: entrees.isEmpty
                          ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          "Aucune entrée enregistrée pour ce filtre.",
                          textAlign: TextAlign.center,
                        ),
                      )
                          : ListView.separated(
                        shrinkWrap: true,
                        itemCount: entrees.length,
                        separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final e = entrees[index];
                          return ListTile(
                            dense: true,
                            isThreeLine: true,
                            leading: Icon(
                              Icons.add_circle,
                              color: e.annulee
                                  ? Colors.grey
                                  : Colors.green.shade700,
                            ),
                            title: Text(
                              _labelTypeEntree(e.type),
                              style: TextStyle(
                                decoration: e.annulee
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            subtitle: Text(
                              "${e.rubriqueAffichee} — ${e.sectionsLabel}\n"
                                  "${e.justification}\n"
                                  "${e.dateFormatee}"
                                  "${e.annulee ? "\nANNULÉE — motif : ${e.motifAnnulation ?? ''}" : ""}",
                              style: TextStyle(
                                fontSize: 11,
                                color: e.annulee ? Colors.red : null,
                              ),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "+${formatMontant(e.montant)} FC",
                                  style: TextStyle(
                                    color: e.annulee
                                        ? Colors.grey
                                        : Colors.green.shade700,
                                    fontWeight: FontWeight.bold,
                                    decoration: e.annulee
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                if (!e.annulee)
                                  InkWell(
                                    onTap: () async {
                                      final ok =
                                      await _annulerEntreeDialog(e);
                                      if (ok) setDialogState(() {});
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.only(top: 4),
                                      child: Icon(Icons.block,
                                          size: 18, color: Colors.red),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
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

  void _openAutresRepartitions() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _AutresRepartitionsScreen(fraisScolaires: fraisScolaires),
      ),
    );
  }

  void _openEvolution() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _EvolutionScreen(fraisScolaires: fraisScolaires),
      ),
    );
  }

  void _openPreuves() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PreuvesPaiementScreen(fraisScolaires: fraisScolaires),
      ),
    );
  }

  String _labelPeriode(String periode) {
    switch (periode) {
      case 'today':
        return "Aujourd'hui";
      case 'month':
        return "Ce mois "
            "(${fraisScolaires.currentSchoolMonthName ?? 'hors année'})";
      case 'year':
      default:
        return "Cette Année (${fraisScolaires.currentYear})";
    }
  }

  Widget _periodeChips(String selected, ValueChanged<String> onChanged) {
    Widget chip(String value, String label) {
      final bool isSelected = selected == value;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: ChoiceChip(
            label: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: isSelected,
            selectedColor: Colors.indigo,
            backgroundColor: Colors.grey.shade200,
            onSelected: (_) => onChanged(value),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('today', "Aujourd'hui"),
        chip('month', "Ce mois"),
        chip('year', "Cette année"),
      ],
    );
  }

  Widget _ligneCategorie(String label, double montant, Color couleur) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration:
                BoxDecoration(color: couleur, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 13)),
            ],
          ),
          Text(
            "-${formatMontant(montant)} FC",
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: couleur),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalCollecte = fraisScolaires.getYearTotalCollected();
    final totalsByClass = fraisScolaires.getTotalByClass();
    final depenses = fraisScolaires.getDepensesForYear();
    final totalDepenses = fraisScolaires.getTotalDepenses();
    final totalEntrees = fraisScolaires.getTotalEntrees();
    final soldeNet = totalCollecte - totalDepenses + totalEntrees;
    final depensesApercu = depenses.take(3).toList();

    final double depGlobales =
    fraisScolaires.getTotalDepensesParPortee(kDepenseGlobale);
    final double depIndep =
    fraisScolaires.getTotalDepensesParPortee(kDepenseIndependante);
    final double depMixtes =
    fraisScolaires.getTotalDepensesParPortee(kDepenseMixte);

    final stats = fraisScolaires.computeDepensesStats(_periodeGlobale);
    final double collectePeriode = stats.totalCollecte;
    final double depensesPeriode = stats.totalDepenses;
    final double soldeNetPeriode = stats.reste;

    final nomsAdmins = fraisScolaires.config.administrations
        .map((a) => a.nom.trim())
        .toSet();
    final rubriquesHorsAdmin = stats.rubriques
        .where((r) =>
    !nomsAdmins.contains(r.rubrique) &&
        (r.total != 0 || r.totalEntrees != 0))
        .toList();

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
                    const Text("Total Collecté Global (Cette Année)",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text("${totalCollecte.toStringAsFixed(0)} FC",
                        style: const TextStyle(
                            fontSize: 24, color: Colors.green)),
                    if (totalDepenses > 0 || totalEntrees > 0) ...[
                      const Divider(height: 24),
                      if (totalDepenses > 0)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Total des dépenses",
                                style: TextStyle(color: Colors.black54)),
                            Text("- ${formatMontant(totalDepenses)} FC",
                                style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      if (totalEntrees > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Total des entrées (dons, retours...)",
                                style: TextStyle(color: Colors.black54)),
                            Text("+ ${formatMontant(totalEntrees)} FC",
                                style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Solde net en caisse",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          Text("${formatMontant(soldeNet)} FC",
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
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _startAddEntree,
                    icon: const Icon(Icons.add_circle),
                    label: const Text("Entrer de l'argent"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openHistoriqueEntreesDialog,
                    icon: const Icon(Icons.history),
                    label: const Text("Historique des entrées"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: Colors.green.shade700,
                      side: BorderSide(color: Colors.green.shade700),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openRapportDepensesDialog,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text("Rapport des dépenses"),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade700),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openAutresRepartitions,
                icon: const Icon(Icons.account_tree),
                label: const Text("Autres Répartitions (par Section)"),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  foregroundColor: Colors.indigo,
                  side: const BorderSide(color: Colors.indigo),
                ),
              ),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openPreuves,
                icon: const Icon(Icons.fact_check),
                label: const Text("Preuves de Paiement (mois par mois)"),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  foregroundColor: Colors.deepPurple,
                  side: const BorderSide(color: Colors.deepPurple),
                ),
              ),
            ),

            const SizedBox(height: 20),

            if (totalDepenses > 0) ...[
              const Text("Dépenses par catégorie (Cette Année)",
                  style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    _ligneCategorie("Globales (toute l'école)", depGlobales,
                        _couleurPortee(kDepenseGlobale)),
                    _ligneCategorie("Indépendantes (une section)", depIndep,
                        _couleurPortee(kDepenseIndependante)),
                    _ligneCategorie("Mixtes (plusieurs sections)", depMixtes,
                        _couleurPortee(kDepenseMixte)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

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
                leading: Icon(Icons.remove_circle_outline,
                    color: _couleurPortee(d.portee)),
                title: Text(d.motif),
                subtitle: Text(
                  "${_labelPortee(d.portee)} — ${d.sectionsLabel}\n"
                      "Rubrique : ${d.rubriqueAffichee} • ${d.dateFormatee}",
                  style: const TextStyle(fontSize: 11),
                ),
                isThreeLine: true,
                trailing: Text(
                  "-${formatMontant(d.montant)} FC",
                  style: TextStyle(
                      color: _couleurPortee(d.portee),
                      fontWeight: FontWeight.bold),
                ),
              )),
              const Divider(),
            ],

            const Text("Montant par Classe (Cette Année)",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ...totalsByClass.entries.map((entry) => ListTile(
              title: Text(entry.key),
              trailing: Text("${entry.value.toStringAsFixed(0)} FC"),
            )),
            const Divider(),

            const Text("Répartition Globale aux Administrations",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              "Ce que chaque administration (enseignants, gestionnaire, "
                  "etc.) a accumulé pour TOUTE L'ÉCOLE sur la période choisie, "
                  "après déduction des dépenses sorties de sa rubrique.",
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            _periodeChips(
              _periodeGlobale,
                  (value) => setState(() => _periodeGlobale = value),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Collecté — ${_labelPeriode(_periodeGlobale)}",
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  Text("${formatMontant(collectePeriode)} FC",
                      style: const TextStyle(
                          fontSize: 18,
                          color: Colors.green,
                          fontWeight: FontWeight.bold)),
                  if (depensesPeriode > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      "Dépenses sur cette période : "
                          "-${formatMontant(depensesPeriode)} FC",
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Solde net sur cette période : "
                          "${formatMontant(soldeNetPeriode)} FC",
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (fraisScolaires.config.administrations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  "Aucune administration configurée (Paramètres).",
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ...fraisScolaires.config.administrations.map((admin) {
                final r = stats.rubriqueParNom(admin.nom.trim());
                final double collecte = r?.collecte ??
                    (collectePeriode * admin.pourcentage / 100);
                final double depense = r?.total ?? 0;
                final double reste = collecte - depense;
                return ListTile(
                  title: Text(admin.nom),
                  subtitle: Text(
                    "${admin.pourcentage}% • Part : ${formatMontant(collecte)} FC"
                        "${depense > 0 ? ' • Dépenses : -${formatMontant(depense)} FC' : ''}",
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Text(
                    "${formatMontant(reste)} FC",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: reste >= 0 ? Colors.black87 : Colors.red,
                    ),
                  ),
                );
              }).toList(),
            ...rubriquesHorsAdmin.map((r) => ListTile(
              title: Text(r.rubrique),
              subtitle: Text(
                "Rubrique hors administration"
                    "${r.total > 0 ? ' — Dépenses : ${formatMontant(r.total)} FC' : ''}"
                    "${r.totalEntrees > 0 ? ' — Entrées : +${formatMontant(r.totalEntrees)} FC' : ''}",
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Text(
                "${r.reste >= 0 ? '' : '-'}${formatMontant(r.reste.abs())} FC",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: r.reste >= 0 ? Colors.indigo : Colors.red),
              ),
            )),
          ],
        ),
      ),
    );
  }
}

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
  String _periode = 'year';

  @override
  void initState() {
    super.initState();
    final options = widget.fraisScolaires.getOptions();
    if (options.isNotEmpty) selectedOption = options.first;
  }

  String _labelPeriode(String periode) {
    switch (periode) {
      case 'today':
        return "Aujourd'hui";
      case 'month':
        return "Ce mois "
            "(${widget.fraisScolaires.currentSchoolMonthName ?? 'hors année'})";
      case 'year':
      default:
        return "Cette Année (${widget.fraisScolaires.currentYear})";
    }
  }

  Widget _periodeChips() {
    Widget chip(String value, String label) {
      final bool isSelected = _periode == value;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: ChoiceChip(
            label: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: isSelected,
            selectedColor: Colors.indigo,
            backgroundColor: Colors.grey.shade200,
            onSelected: (_) => setState(() => _periode = value),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('today', "Aujourd'hui"),
        chip('month', "Ce mois"),
        chip('year', "Cette année"),
      ],
    );
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
                "Les totaux par option/section sont BRUTS (avant "
                    "dépenses). Dans le détail d'une option, le « reste » de "
                    "chaque administration déduit les dépenses indépendantes "
                    "et mixtes rattachées à cette section. Les dépenses "
                    "globales de l'école ne sont pas déduites ici.",
                style: TextStyle(fontSize: 12, color: Colors.indigo),
              ),
            ),
            const SizedBox(height: 12),

            const Text("Période",
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _periodeChips(),
            const SizedBox(height: 16),

            Text("Vue d'ensemble par Option — ${_labelPeriode(_periode)}",
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...options.map((option) {
              final detail = fraisScolaires.getRepartitionForOptionPeriod(
                  option, _periode);
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

            Text("Détail par Option — ${_labelPeriode(_periode)}",
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
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
    final detailOption =
    fraisScolaires.getRepartitionForOptionPeriod(option, _periode);
    final hasSousSections = fraisScolaires.optionHasSousSections(option);
    final sousSections =
    fraisScolaires.getSousSectionsForOptionPeriod(option, _periode);

    final stats = fraisScolaires.computeDepensesStats(
      _periode,
      sectionFilter: option,
    );
    final rubriquesAffichees = stats.rubriques
        .where((r) => r.collecte != 0 || r.total != 0 || r.totalEntrees != 0)
        .toList();

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
                  "Total $option — ${_labelPeriode(_periode)}",
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
                if (stats.totalDepenses > 0 || stats.totalEntrees > 0) ...[
                  const SizedBox(height: 6),
                  if (stats.totalDepenses > 0)
                    Text(
                      "Dépenses de la section : "
                          "-${formatMontant(stats.totalDepenses)} FC",
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  if (stats.totalEntrees > 0)
                    Text(
                      "Entrées de la section : "
                          "+${formatMontant(stats.totalEntrees)} FC",
                      style:
                      const TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  Text(
                    "Reste après dépenses : ${formatMontant(stats.reste)} FC",
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo),
                  ),
                ],
                const SizedBox(height: 12),
                const Text("Répartition par administration :",
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                if (rubriquesAffichees.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      "Aucune administration configurée.",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  )
                else
                  ...rubriquesAffichees.map(
                        (r) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.rubrique),
                                Text(
                                  "Part : ${formatMontant(r.collecte)} FC"
                                      "${r.total > 0 ? ' − Dépenses : ${formatMontant(r.total)} FC' : ''}"
                                      "${r.totalEntrees > 0 ? ' + Entrées : ${formatMontant(r.totalEntrees)} FC' : ''}",
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            "${formatMontant(r.reste)} FC",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: r.reste >= 0
                                  ? Colors.black87
                                  : Colors.red,
                            ),
                          ),
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
            "Détail par Section ($option) — ${_labelPeriode(_periode)}",
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
              children: detail.parAdministration.isEmpty
                  ? [
                const Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Text(
                    "Aucune administration configurée.",
                    style:
                    TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ]
                  : detail.parAdministration.entries
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

class _EvolutionScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const _EvolutionScreen({required this.fraisScolaires});

  @override
  State<_EvolutionScreen> createState() => _EvolutionScreenState();
}

class _EvolutionScreenState extends State<_EvolutionScreen> {
  String? selectedOption;
  String? selectedSousSection;
  String? selectedClasse;
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

class _PaiementPreuve {
  final Eleve eleve;
  final Map<String, dynamic> transaction;
  final bool archive;

  const _PaiementPreuve({
    required this.eleve,
    required this.transaction,
    required this.archive,
  });

  String get date => transaction['date']?.toString().trim() ?? '';

  double get montant => (transaction['amount'] as num?)?.toDouble() ?? 0.0;

  String get nomComplet =>
      '${eleve.nom} ${eleve.postNom} ${eleve.prenom}'
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
}

class _JourPreuve {
  final String date;
  final List<_PaiementPreuve> paiements;

  const _JourPreuve({required this.date, required this.paiements});

  double get total => paiements.fold(0.0, (s, p) => s + p.montant);

  int get nbEleves => paiements.map((p) => p.eleve.id).toSet().length;
}

class _EcartEleve {
  final Eleve eleve;
  final bool archive;
  final double paye;
  final double justifie;

  const _EcartEleve({
    required this.eleve,
    required this.archive,
    required this.paye,
    required this.justifie,
  });

  double get difference => paye - justifie;

  String get nomComplet =>
      '${eleve.nom} ${eleve.postNom} ${eleve.prenom}'
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
}

class _MoisPreuve {
  final String mois;
  final double paye;
  final double justifie;
  final double attendu;
  final double reste;
  final List<_JourPreuve> jours;
  final List<_EcartEleve> ecarts;

  const _MoisPreuve({
    required this.mois,
    required this.paye,
    required this.justifie,
    required this.attendu,
    required this.reste,
    required this.jours,
    required this.ecarts,
  });

  int get nbPaiements => jours.fold(0, (s, j) => s + j.paiements.length);

  int get nbJours => jours.length;

  double get sansDetail => paye - justifie;

  bool get aEcart => sansDetail.abs() > 0.5;
}

class _PreuvesCalcul {
  static final RegExp _iso = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static bool dateValide(String d) => _iso.hasMatch(d);

  static String _deux(int n) => n.toString().padLeft(2, '0');

  static String affDate(String iso) {
    if (iso.isEmpty) return 'Date inconnue';
    if (dateValide(iso)) {
      final p = iso.split('-');
      return '${p[2]}/${p[1]}/${p[0]}';
    }
    return iso;
  }

  static String affDateHeure(DateTime d) =>
      '${_deux(d.day)}/${_deux(d.month)}/${d.year} ${_deux(d.hour)}:${_deux(d.minute)}';

  static String affDateHeureIso(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return iso ?? '';
    return affDateHeure(d);
  }

  static List<MapEntry<Eleve, bool>> eleves(
      FraisScolaires fs, {
        String? section,
        String? classe,
        required bool archives,
      }) {
    final result = <MapEntry<Eleve, bool>>[];
    void ajouter(Eleve e, bool arch) {
      if (section != null && e.section != section) return;
      if (classe != null && e.classe != classe) return;
      result.add(MapEntry(e, arch));
    }

    for (final e in fs.currentData.eleves) {
      ajouter(e, false);
    }
    if (archives) {
      for (final e in fs.elevesSupprimesData.eleves) {
        ajouter(e, true);
      }
    }
    return result;
  }

  static List<_MoisPreuve> calculer(
      FraisScolaires fs, List<MapEntry<Eleve, bool>> eleves) {
    final result = <_MoisPreuve>[];
    for (final mois in fs.months) {
      double paye = 0;
      double justifie = 0;
      double attendu = 0;
      double reste = 0;
      final Map<String, List<_PaiementPreuve>> parDate = {};
      final List<_EcartEleve> ecarts = [];

      for (final entry in eleves) {
        final Eleve e = entry.key;
        final bool archive = entry.value;
        final double payeEleve = e.paid[mois] ?? 0.0;
        final double requis = fs.getRequiredForMonthForEleve(e, mois);
        double justifieEleve = 0;

        for (final t in e.transactions) {
          if (t['mois']?.toString() != mois) continue;
          final p = _PaiementPreuve(eleve: e, transaction: t, archive: archive);
          justifieEleve += p.montant;
          parDate.putIfAbsent(p.date, () => <_PaiementPreuve>[]).add(p);
        }

        paye += payeEleve;
        justifie += justifieEleve;
        attendu += requis;
        final double manque = requis - payeEleve;
        if (manque > 0) reste += manque;

        if ((payeEleve - justifieEleve).abs() > 0.5) {
          ecarts.add(_EcartEleve(
            eleve: e,
            archive: archive,
            paye: payeEleve,
            justifie: justifieEleve,
          ));
        }
      }

      final dates = parDate.keys.toList();
      dates.sort((a, b) {
        final va = dateValide(a);
        final vb = dateValide(b);
        if (va && !vb) return -1;
        if (!va && vb) return 1;
        return a.compareTo(b);
      });

      final jours = <_JourPreuve>[];
      for (final d in dates) {
        final liste = parDate[d]!;
        liste.sort((a, b) {
          final c = a.eleve.classe.compareTo(b.eleve.classe);
          if (c != 0) return c;
          return a.nomComplet.toLowerCase().compareTo(b.nomComplet.toLowerCase());
        });
        jours.add(_JourPreuve(date: d, paiements: liste));
      }

      ecarts.sort((a, b) =>
          a.nomComplet.toLowerCase().compareTo(b.nomComplet.toLowerCase()));

      result.add(_MoisPreuve(
        mois: mois,
        paye: paye,
        justifie: justifie,
        attendu: attendu,
        reste: reste,
        jours: jours,
        ecarts: ecarts,
      ));
    }
    return result;
  }

  static List<_PaiementPreuve> moisInconnus(
      FraisScolaires fs, List<MapEntry<Eleve, bool>> eleves) {
    final result = <_PaiementPreuve>[];
    for (final entry in eleves) {
      for (final t in entry.key.transactions) {
        final String m = t['mois']?.toString() ?? '';
        if (!fs.months.contains(m)) {
          result.add(_PaiementPreuve(
              eleve: entry.key, transaction: t, archive: entry.value));
        }
      }
    }
    return result;
  }

  static List<String> notes(_PaiementPreuve p) {
    final t = p.transaction;
    final result = <String>[];
    if (p.archive) result.add('Élève supprimé (archivé)');
    if (t['saisieGroupee'] == true) {
      result.add('Ancien paiement du cahier (saisie groupée, lot ${t['lotSaisie'] ?? ''})');
    } else if (t['from_parent'] == true) {
      result.add('Paiement mobile (${t['network'] ?? 'Mobile Money'})');
    } else if (t['receiptConfirmed'] == true) {
      result.add('Reçu imprimé');
    } else {
      result.add('Reçu non imprimé ou en attente');
    }
    final String dateOriginale = t['dateOriginale']?.toString() ?? '';
    if (dateOriginale.isNotEmpty) {
      final String quand = t['dateModifieeLe']?.toString() ?? '';
      result.add('Date corrigée : ancienne date ${affDate(dateOriginale)}'
          '${quand.isNotEmpty ? ' (corrigée le ${affDateHeureIso(quand)})' : ''}');
    }
    final String modifiePar = t['modifiePar']?.toString() ?? '';
    if (modifiePar.isNotEmpty) {
      final String le = t['modifieLe']?.toString() ?? '';
      result.add('Montant modifié par $modifiePar'
          '${le.isNotEmpty ? ' le ${affDate(le)}' : ''}');
    }
    if (t['excedent'] == true) {
      result.add('Excédent placé sur le dernier mois');
    }
    if (t['moisDebloque'] == true) {
      result.add('Mois déverrouillé');
    }
    final String id = t['id']?.toString() ?? '';
    if (id.isNotEmpty) result.add('Réf : $id');
    return result;
  }
}

class _PreuvesTexte {
  static void _blocMois(StringBuffer b, _MoisPreuve m) {
    b.writeln('=== ${m.mois.toUpperCase()} ===');
    b.writeln('Total payé : ${formatMontant(m.paye)} FC');
    b.writeln('Somme des paiements datés : ${formatMontant(m.justifie)} FC');
    if (m.aEcart) {
      b.writeln('Écart (montant sans détail de date) : '
          '${formatMontant(m.sansDetail)} FC');
    }
    b.writeln('Nombre de paiements : ${m.nbPaiements} sur ${m.nbJours} jour(s)');
    for (final j in m.jours) {
      b.writeln('');
      b.writeln('${_PreuvesCalcul.affDate(j.date)} — '
          '${j.paiements.length} paiement(s) — ${formatMontant(j.total)} FC');
      for (final p in j.paiements) {
        b.writeln('  • ${p.nomComplet} (${p.eleve.classe}, ${p.eleve.section}) : '
            '${formatMontant(p.montant)} FC');
        for (final n in _PreuvesCalcul.notes(p)) {
          b.writeln('      - $n');
        }
      }
    }
    if (m.ecarts.isNotEmpty) {
      b.writeln('');
      b.writeln('Élèves dont le montant du mois n\'a pas le même détail :');
      for (final e in m.ecarts) {
        b.writeln('  • ${e.nomComplet} (${e.eleve.classe}) : enregistré '
            '${formatMontant(e.paye)} FC, paiements datés '
            '${formatMontant(e.justifie)} FC, écart '
            '${formatMontant(e.difference)} FC');
      }
    }
    b.writeln('');
  }

  static void _entete(StringBuffer b, FraisScolaires fs, String titre,
      String portee, bool archives) {
    b.writeln(titre);
    b.writeln(fs.config.schoolName);
    b.writeln('Année scolaire : ${fs.currentYear}');
    b.writeln('Portée : $portee');
    b.writeln(archives
        ? 'Élèves supprimés (archivés) : inclus'
        : 'Élèves supprimés (archivés) : non inclus');
    b.writeln('Généré le ${_PreuvesCalcul.affDateHeure(DateTime.now())}');
    b.writeln('');
  }

  static String mois(FraisScolaires fs, String portee, bool archives,
      _MoisPreuve m) {
    final b = StringBuffer();
    _entete(b, fs, 'PREUVES DE PAIEMENT — ${m.mois}', portee, archives);
    _blocMois(b, m);
    return b.toString();
  }

  static String annee(FraisScolaires fs, String portee, bool archives,
      List<_MoisPreuve> liste) {
    final b = StringBuffer();
    _entete(b, fs, 'PREUVES DE PAIEMENT — TOUS LES MOIS', portee, archives);
    double total = 0;
    for (final m in liste) {
      total += m.paye;
    }
    b.writeln('Total payé sur l\'année : ${formatMontant(total)} FC');
    b.writeln('');
    for (final m in liste) {
      _blocMois(b, m);
    }
    return b.toString();
  }
}

class _PreuvesPaiementScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const _PreuvesPaiementScreen({required this.fraisScolaires});

  @override
  State<_PreuvesPaiementScreen> createState() =>
      _PreuvesPaiementScreenState();
}

class _PreuvesPaiementScreenState extends State<_PreuvesPaiementScreen> {
  String? _section;
  String? _classe;
  bool _archives = true;

  FraisScolaires get fs => widget.fraisScolaires;

  String get _portee {
    if (_section == null && _classe == null) return "Toute l'école";
    final parts = <String>[];
    if (_section != null) parts.add("Section : $_section");
    if (_classe != null) parts.add("Classe : $_classe");
    return parts.join(' — ');
  }

  List<String> _sectionsDisponibles() {
    final set = LinkedHashSet<String>.from(fs.config.sections);
    for (final e in fs.currentData.eleves) {
      if (e.section.trim().isNotEmpty) set.add(e.section);
    }
    if (_archives) {
      for (final e in fs.elevesSupprimesData.eleves) {
        if (e.section.trim().isNotEmpty) set.add(e.section);
      }
    }
    return set.toList();
  }

  List<String> _classesDisponibles() {
    final set = LinkedHashSet<String>();
    set.addAll(_section != null
        ? fs.getAllDisplayClassesForSection(_section!)
        : fs.getAllDisplayClasses());
    final tous = <Eleve>[
      ...fs.currentData.eleves,
      if (_archives) ...fs.elevesSupprimesData.eleves,
    ];
    for (final e in tous) {
      if (_section != null && e.section != _section) continue;
      if (e.classe.trim().isNotEmpty) set.add(e.classe);
    }
    return set.toList();
  }

  void _copier(String texte, String message) {
    Clipboard.setData(ClipboardData(text: texte));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Widget _ligneResume(String label, double valeur, Color couleur,
      {bool gras = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: gras ? FontWeight.bold : FontWeight.normal)),
          ),
          Text("${formatMontant(valeur)} FC",
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: couleur)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sectionsDisponibles();
    if (_section != null && !sections.contains(_section)) {
      sections.add(_section!);
    }
    final classes = _classesDisponibles();
    if (_classe != null && !classes.contains(_classe)) {
      classes.add(_classe!);
    }

    final eleves = _PreuvesCalcul.eleves(
      fs,
      section: _section,
      classe: _classe,
      archives: _archives,
    );
    final liste = _PreuvesCalcul.calculer(fs, eleves);
    final inconnus = _PreuvesCalcul.moisInconnus(fs, eleves);

    double totalPaye = 0;
    double totalJustifie = 0;
    double totalAttendu = 0;
    double totalReste = 0;
    for (final m in liste) {
      totalPaye += m.paye;
      totalJustifie += m.justifie;
      totalAttendu += m.attendu;
      totalReste += m.reste;
    }
    final double totalSansDetail = totalPaye - totalJustifie;
    final String? moisCourant = fs.currentSchoolMonthName;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Preuves de Paiement"),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: "Copier le relevé de tous les mois",
            onPressed: () => _copier(
              _PreuvesTexte.annee(fs, _portee, _archives, liste),
              "Relevé de tous les mois copié. Vous pouvez le coller dans "
                  "un message ou un document.",
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "Choisissez toute l'école, une section ou une classe. "
                    "Appuyez ensuite sur un mois pour voir chaque jour où "
                    "l'argent est entré, avec le nom de chaque élève, le "
                    "montant et la référence du paiement.",
                style: TextStyle(fontSize: 12, color: Colors.deepPurple),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              value: _section,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: "Section",
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text("Toutes les sections")),
                ...sections.map((s) =>
                    DropdownMenuItem<String?>(value: s, child: Text(s))),
              ],
              onChanged: (v) {
                setState(() {
                  _section = v;
                  if (_classe != null &&
                      !_classesDisponibles().contains(_classe)) {
                    _classe = null;
                  }
                });
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              value: _classe,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: "Classe",
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text("Toutes les classes")),
                ...classes.map((c) =>
                    DropdownMenuItem<String?>(value: c, child: Text(c))),
              ],
              onChanged: (v) => setState(() => _classe = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _archives,
              onChanged: (v) {
                setState(() {
                  _archives = v;
                  if (_section != null &&
                      !_sectionsDisponibles().contains(_section)) {
                    _section = null;
                  }
                  if (_classe != null &&
                      !_classesDisponibles().contains(_classe)) {
                    _classe = null;
                  }
                });
              },
              title: const Text("Inclure les élèves supprimés (archivés)",
                  style: TextStyle(fontSize: 13)),
              subtitle: const Text(
                "Les totaux de l'application les comptent aussi. Gardez cette "
                    "option activée pour retrouver exactement les mêmes totaux.",
                style: TextStyle(fontSize: 11),
              ),
            ),
            const SizedBox(height: 6),
            Card(
              color: Colors.deepPurple.withAlpha(15),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "$_portee — ${eleves.length} élève(s)",
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _ligneResume("Total payé sur l'année", totalPaye,
                        Colors.green.shade700,
                        gras: true),
                    _ligneResume("Justifié par des paiements datés",
                        totalJustifie, Colors.indigo),
                    if (totalSansDetail.abs() > 0.5)
                      _ligneResume("Sans détail de date (écart)",
                          totalSansDetail, Colors.orange.shade800),
                    const Divider(height: 18),
                    _ligneResume("Montant attendu sur l'année", totalAttendu,
                        Colors.black87),
                    _ligneResume("Reste à payer", totalReste, Colors.red),
                  ],
                ),
              ),
            ),
            if (inconnus.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(30),
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "Attention : ${inconnus.length} paiement(s) portent un "
                      "mois inconnu (hors calendrier scolaire), pour "
                      "${formatMontant(inconnus.fold(0.0, (s, p) => s + p.montant))} FC. "
                      "Ils n'apparaissent dans aucun mois ci-dessous.",
                  style: const TextStyle(fontSize: 12, color: Colors.deepOrange),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text("Mois de l'année",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...liste.map((m) {
              final bool aDesPaiements = m.paye > 0 || m.nbPaiements > 0;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    aDesPaiements ? Icons.check_circle : Icons.remove_circle_outline,
                    color: aDesPaiements ? Colors.green : Colors.grey,
                  ),
                  title: Text(
                    m.mois == moisCourant ? "${m.mois} (mois actuel)" : m.mois,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    m.nbPaiements == 0
                        ? "Aucun paiement daté pour ce mois"
                        : "${m.nbPaiements} paiement(s) • ${m.nbJours} jour(s)"
                        "${m.aEcart ? '\n⚠ Écart de ${formatMontant(m.sansDetail)} FC sans détail de date' : ''}",
                    style: TextStyle(
                      fontSize: 12,
                      color: m.aEcart ? Colors.deepOrange : null,
                    ),
                  ),
                  isThreeLine: m.aEcart && m.nbPaiements > 0,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "${formatMontant(m.paye)} FC",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_ios, size: 14),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _PreuvesMoisScreen(
                          fraisScolaires: fs,
                          mois: m,
                          portee: _portee,
                          archives: _archives,
                        ),
                      ),
                    );
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _PreuvesMoisScreen extends StatelessWidget {
  final FraisScolaires fraisScolaires;
  final _MoisPreuve mois;
  final String portee;
  final bool archives;

  const _PreuvesMoisScreen({
    required this.fraisScolaires,
    required this.mois,
    required this.portee,
    required this.archives,
  });

  Widget _ligne(String label, String valeur, Color couleur,
      {bool gras = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: gras ? FontWeight.bold : FontWeight.normal)),
          ),
          Text(valeur,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: couleur)),
        ],
      ),
    );
  }

  Widget _jour(_JourPreuve j) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                _PreuvesCalcul.affDate(j.date),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              "${formatMontant(j.total)} FC",
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.green.shade700),
            ),
          ],
        ),
        subtitle: Text(
          "${j.paiements.length} paiement(s) • ${j.nbEleves} élève(s)",
          style: const TextStyle(fontSize: 12),
        ),
        children: j.paiements.map((p) {
          final notes = _PreuvesCalcul.notes(p);
          return ListTile(
            dense: true,
            isThreeLine: true,
            title: Text(p.nomComplet,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              "${p.eleve.classe} • ${p.eleve.section}\n${notes.join('\n')}",
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Text(
              "${formatMontant(p.montant)} FC",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fs = fraisScolaires;
    final m = mois;

    return Scaffold(
      appBar: AppBar(
        title: Text("Preuves — ${m.mois}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            tooltip: "Copier le relevé de ce mois",
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: _PreuvesTexte.mois(fs, portee, archives, m)));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Relevé du mois copié. Vous pouvez le coller "
                      "dans un message ou un document."),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.deepPurple.withAlpha(15),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${m.mois} — $portee",
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "Année scolaire ${fs.currentYear}",
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 8),
                    _ligne("Total payé pour ce mois",
                        "${formatMontant(m.paye)} FC", Colors.green.shade700,
                        gras: true),
                    _ligne("Somme des paiements datés",
                        "${formatMontant(m.justifie)} FC", Colors.indigo),
                    if (m.aEcart)
                      _ligne("Écart sans détail de date",
                          "${formatMontant(m.sansDetail)} FC",
                          Colors.orange.shade800),
                    _ligne("Nombre de paiements", "${m.nbPaiements}",
                        Colors.black87),
                    _ligne("Nombre de jours", "${m.nbJours}", Colors.black87),
                    const Divider(height: 18),
                    _ligne("Montant attendu pour ce mois",
                        "${formatMontant(m.attendu)} FC", Colors.black87),
                    _ligne("Reste à payer pour ce mois",
                        "${formatMontant(m.reste)} FC", Colors.red),
                  ],
                ),
              ),
            ),
            if (m.aEcart) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(30),
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  m.sansDetail > 0
                      ? "Le montant enregistré pour ce mois "
                      "(${formatMontant(m.paye)} FC) est plus grand que la "
                      "somme des paiements datés (${formatMontant(m.justifie)} FC). "
                      "Il manque le détail de ${formatMontant(m.sansDetail)} FC : "
                      "ce sont de très anciens paiements enregistrés sans "
                      "historique. La liste des élèves concernés est en bas de la page."
                      : "La somme des paiements datés (${formatMontant(m.justifie)} FC) "
                      "est plus grande que le montant enregistré pour ce mois "
                      "(${formatMontant(m.paye)} FC). La liste des élèves "
                      "concernés est en bas de la page.",
                  style: const TextStyle(fontSize: 12, color: Colors.deepOrange),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text("Jour par jour",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (m.jours.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    "Aucun paiement daté pour ce mois.",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ...m.jours.map(_jour),
            if (m.jours.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Total de tous les jours",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      "${formatMontant(m.justifie)} FC",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700),
                    ),
                  ],
                ),
              ),
            if (m.ecarts.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text("Élèves avec un écart",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                "Pour ces élèves, le montant enregistré pour le mois n'est "
                    "pas égal à la somme de leurs paiements datés.",
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              ...m.ecarts.map((e) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  isThreeLine: true,
                  title: Text(e.nomComplet,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    "${e.eleve.classe} • ${e.eleve.section}"
                        "${e.archive ? ' • élève supprimé (archivé)' : ''}\n"
                        "Enregistré : ${formatMontant(e.paye)} FC • "
                        "Paiements datés : ${formatMontant(e.justifie)} FC",
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Text(
                    "${formatMontant(e.difference)} FC",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800),
                  ),
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }
}