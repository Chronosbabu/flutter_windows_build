import 'package:flutter/material.dart';
import '../frais_scolaires.dart';
import '../models.dart';
import 'recouvrement_autres_frais_screen.dart';

class AutresFraisScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const AutresFraisScreen({super.key, required this.fraisScolaires});

  @override
  State<AutresFraisScreen> createState() => _AutresFraisScreenState();
}

class _AutresFraisScreenState extends State<AutresFraisScreen> {
  static const String _libelleSansTranche = "Paiement unique / avant tranches";

  final searchController = TextEditingController();
  AutreFrais? selectedFrais;
  final Set<String> selectedStudentIds = {};
  bool _processing = false;

  String? filterSection;
  String? filterClasse;

  int _tapCount = 0;
  String? _tapEleveId;
  DateTime? _tapDernier;
  bool _selectionAvantTaps = false;

  @override
  void initState() {
    super.initState();
    final frais = widget.fraisScolaires.getAutresFrais();
    if (frais.isNotEmpty) selectedFrais = frais.first;
    searchController.addListener(() => setState(() {}));
    _flushPendingReceipts();
  }

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

  // ⚡ NOUVEAU — résumé lisible de l'état des tranches d'un élève.
  static String _fc(double v) => "${v.toStringAsFixed(0)} FC";

  static String _libelleEtatsTranches(AutreFraisStatut statut) {
    return statut.etatsTranches.map((e) {
      switch (e.etat) {
        case AutreFraisEtatTranche.payee:
          return "${e.tranche.nom} : payée";
        case AutreFraisEtatTranche.partielle:
          return "${e.tranche.nom} : partielle (${_fc(e.verse)} versés, "
              "reste ${_fc(e.reste)})";
        case AutreFraisEtatTranche.nonPayee:
          return "${e.tranche.nom} : non payée";
      }
    }).join("\n");
  }

  void _ouvrirRecouvrement() {
    if (selectedFrais == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecouvrementAutresFraisScreen(
          fraisScolaires: widget.fraisScolaires,
          frais: selectedFrais!,
          sectionInitiale: filterSection,
          classeInitiale: filterClasse,
        ),
      ),
    );
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

  void _enregistrerTap(Eleve eleve) {
    if (selectedFrais == null) return;
    final now = DateTime.now();
    if (_tapEleveId == eleve.id &&
        _tapDernier != null &&
        now.difference(_tapDernier!).inMilliseconds < 700) {
      _tapCount++;
    } else {
      _tapEleveId = eleve.id;
      _tapCount = 1;
      _selectionAvantTaps = selectedStudentIds.contains(eleve.id);
    }
    _tapDernier = now;

    if (_tapCount >= 3) {
      _tapCount = 0;
      final bool avant = _selectionAvantTaps;
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        setState(() {
          if (avant) {
            selectedStudentIds.add(eleve.id);
          } else {
            selectedStudentIds.remove(eleve.id);
          }
        });
        _ouvrirGestionPaiements(eleve);
      });
    }
  }

  void _ouvrirGestionPaiements(Eleve eleve) {
    if (selectedFrais == null) return;
    final frais = selectedFrais!;
    final fs = widget.fraisScolaires;
    if (fs.getPaiementsEleveAutreFrais(eleve, frais).isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final List<AutreFraisPaiement> paiements =
          fs.getPaiementsEleveAutreFrais(eleve, frais)
            ..sort((a, b) => a.date.compareTo(b.date));
          final statut = fs.getStatutAutreFrais(frais, eleve);

          final historique = fs
              .getAdminAuditLog()
              .where((a) =>
          a.eleveId == eleve.id &&
              a.mois.toString().startsWith('Autres frais : ${frais.nom}'))
              .toList();

          Future<void> rafraichir() async {
            setDialogState(() {});
            if (mounted) setState(() {});
          }

          Future<void> annuler(AutreFraisPaiement p) async {
            final bool? confirme = await showDialog<bool>(
              context: ctx,
              builder: (ctx2) => AlertDialog(
                title: const Text("Annuler ce paiement ?"),
                content: Text(
                  "${fs.libelleTranchePaiementAutreFrais(p)} — "
                      "${p.montant.toStringAsFixed(0)} FC\n"
                      "${eleve.nom} ${eleve.prenom}\n\n"
                      "Le paiement sera retiré et les totaux seront "
                      "recalculés. L'annulation sera signalée dans le "
                      "journal.",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx2, false),
                    child: const Text("Retour"),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white),
                    onPressed: () => Navigator.pop(ctx2, true),
                    child: const Text("Annuler le paiement"),
                  ),
                ],
              ),
            );
            if (confirme != true) return;
            try {
              await fs.annulerPaiementAutreFrais(
                  paiement: p, eleve: eleve);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        "✅ Paiement annulé : ${frais.nom} "
                            "(${fs.libelleTranchePaiementAutreFrais(p)}) "
                            "pour ${eleve.nom} ${eleve.prenom}"),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("❌ Annulation impossible : $e"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
            await rafraichir();
          }

          Future<void> modifier(AutreFraisPaiement p) async {
            final ctrl =
            TextEditingController(text: p.montant.toStringAsFixed(0));
            final double? nouveau = await showDialog<double>(
              context: ctx,
              builder: (ctx2) => AlertDialog(
                title: const Text("Modifier le paiement"),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${fs.libelleTranchePaiementAutreFrais(p)}\n"
                          "Montant actuel : ${p.montant.toStringAsFixed(0)} FC",
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ctrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Nouveau montant (FC)",
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx2),
                    child: const Text("Retour"),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final v = double.tryParse(ctrl.text
                          .trim()
                          .replaceAll(' ', '')
                          .replaceAll(',', '.'));
                      if (v == null || v <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Veuillez entrer un montant valide"),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(ctx2, v);
                    },
                    child: const Text("Enregistrer"),
                  ),
                ],
              ),
            );
            if (nouveau == null) return;
            try {
              await fs.modifierMontantPaiementAutreFrais(
                paiement: p,
                eleve: eleve,
                newMontant: nouveau,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        "✅ Paiement modifié : ${p.montant.toStringAsFixed(0)} "
                            "→ ${nouveau.toStringAsFixed(0)} FC "
                            "(${frais.nom})"),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("❌ Modification impossible : $e"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
            await rafraichir();
          }

          String dateAudit(dynamic d) =>
              d.toString().replaceAll('T', ' ').split(' ')[0];

          return AlertDialog(
            title: Text("${eleve.nom} ${eleve.prenom} — ${frais.nom}"),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "Total dû : ${_fc(statut.totalDu)}\n"
                            "Déjà payé : ${_fc(statut.totalPaye)}\n"
                            "Reste à payer : ${_fc(statut.reste)}"
                            "${statut.tranches.isNotEmpty ? '\n${_libelleEtatsTranches(statut)}' : ''}",
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Paiements enregistrés",
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo),
                    ),
                    const SizedBox(height: 6),
                    if (paiements.isEmpty)
                      const Text(
                        "Aucun paiement pour ce frais.",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      )
                    else
                      ...paiements.map((p) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fs.libelleTranchePaiementAutreFrais(p),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500),
                                    ),
                                    Text(
                                      "${p.montant.toStringAsFixed(0)} FC  •  ${p.dateFormatee}",
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
                                onPressed: () => modifier(p),
                              ),
                              IconButton(
                                icon: const Icon(Icons.cancel_outlined,
                                    size: 18, color: Colors.red),
                                tooltip: "Annuler",
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 32, minHeight: 32),
                                onPressed: () => annuler(p),
                              ),
                            ],
                          ),
                        );
                      }),
                    if (historique.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text(
                        "Historique des annulations / modifications",
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange),
                      ),
                      const SizedBox(height: 6),
                      ...historique.map((a) {
                        final bool estAnnulation = a.action == 'annulation';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            estAnnulation
                                ? "• ${dateAudit(a.date)} — ANNULÉ : ${a.mois} "
                                "(${a.montantAvant.toStringAsFixed(0)} FC)"
                                : "• ${dateAudit(a.date)} — MODIFIÉ : ${a.mois} "
                                "(${a.montantAvant.toStringAsFixed(0)} → "
                                "${a.montantApres.toStringAsFixed(0)} FC)",
                            style: const TextStyle(
                                fontSize: 11, color: Colors.orange),
                          ),
                        );
                      }),
                    ],
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

  Future<void> _payerUnSeul(Eleve eleve, {double? montant}) async {
    if (selectedFrais == null) return;
    if (widget.fraisScolaires.hasPaidAutreFrais(eleve, selectedFrais!)) return;
    setState(() => _processing = true);
    final frais = selectedFrais!;
    try {
      final paiement = await widget.fraisScolaires
          .payAutreFrais(frais: frais, eleve: eleve, montantSaisi: montant);
      final apres = widget.fraisScolaires.getStatutAutreFrais(frais, eleve);
      final printed = await widget.fraisScolaires.printOrQueueAutreFraisReceipt(
        eleve: eleve,
        frais: frais,
        paiement: paiement,
      );
      final String libelleTranche = paiement.trancheLibelle.isEmpty
          ? ''
          : ' (${paiement.trancheLibelle})';
      if (mounted) {
        setState(() {
          selectedStudentIds.remove(eleve.id);
          _processing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              printed
                  ? "✅ ${frais.nom}$libelleTranche : ${_fc(paiement.montant)} enregistrés et reçu imprimé pour ${eleve.nom} ${eleve.prenom} — reste ${_fc(apres.reste)}"
                  : "✅ ${frais.nom}$libelleTranche : ${_fc(paiement.montant)} enregistrés pour ${eleve.nom} ${eleve.prenom} — reste ${_fc(apres.reste)} — reçu en attente d'impression",
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Paiement impossible : $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
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
      try {
        final paiement = await widget.fraisScolaires
            .payAutreFrais(frais: frais, eleve: eleve);
        success++;
        final printed =
        await widget.fraisScolaires.printOrQueueAutreFraisReceipt(
          eleve: eleve,
          frais: frais,
          paiement: paiement,
        );
        if (printed) printedCount++;
      } catch (_) {}
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

  // ⚡ NOUVEAU — fenêtre de paiement : tranche entière OU montant libre.
  void _confirmPaiementUnique(Eleve eleve) {
    if (selectedFrais == null) return;
    final frais = selectedFrais!;
    final fs = widget.fraisScolaires;
    final statut = fs.getStatutAutreFrais(frais, eleve);
    if (statut.solde || statut.reste <= 0) return;
    // Tranche entière = reste de la prochaine tranche ; sans tranches = reste
    // du frais (le montant plein s'il n'y a encore aucun paiement).
    final double montantEntier =
    statut.tranches.isNotEmpty ? statut.montantProchain : statut.reste;
    String libelleEntier;
    if (statut.prochaine != null) {
      final idx =
      statut.tranches.indexWhere((t) => t.id == statut.prochaine!.id);
      libelleEntier = statut.prochaine!.estMois
          ? "Payer le mois entier : ${statut.prochaine!.mois} "
          "(${idx + 1}/${statut.tranches.length}) — ${_fc(montantEntier)}"
          : "Payer la tranche entière : ${statut.prochaine!.nom} "
          "(${idx + 1}/${statut.tranches.length}) — ${_fc(montantEntier)}";
    } else {
      libelleEntier = statut.totalPaye > 0
          ? "Payer le reste — ${_fc(montantEntier)}"
          : "Payer en entier — ${_fc(montantEntier)}";
    }
    final ctrl = TextEditingController();
    String? erreur;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void validerSaisie() {
            final v = double.tryParse(ctrl.text
                .trim()
                .replaceAll(' ', '')
                .replaceAll(',', '.'));
            if (v == null || v <= 0) {
              setDialogState(
                      () => erreur = "Entrez un montant supérieur à zéro.");
              return;
            }
            if (v > statut.reste + 0.5) {
              setDialogState(() => erreur =
              "Montant trop élevé. Maximum possible : ${_fc(statut.reste)}.");
              return;
            }
            Navigator.pop(ctx);
            _payerUnSeul(eleve, montant: v);
          }

          return AlertDialog(
            title: Text(frais.nom),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${eleve.nom} ${eleve.postNom} ${eleve.prenom} "
                          "(${eleve.classe})",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "Total dû : ${_fc(statut.totalDu)}\n"
                            "Déjà payé : ${_fc(statut.totalPaye)}\n"
                            "Reste à payer : ${_fc(statut.reste)}"
                            "${statut.tranches.isNotEmpty ? '\n\n${_libelleEtatsTranches(statut)}' : ''}",
                        style: const TextStyle(
                            fontSize: 12, color: Colors.indigo),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.done_all),
                        label: Text(libelleEntier),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: montantEntier <= 0
                            ? null
                            : () {
                          Navigator.pop(ctx);
                          _payerUnSeul(eleve);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Ou saisir le montant apporté par le parent :",
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: ctrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        labelText: "Montant (FC)",
                        helperText: "Maximum : ${_fc(statut.reste)}",
                        errorText: erreur,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        if (erreur != null) {
                          setDialogState(() => erreur = null);
                        }
                      },
                      onSubmitted: (_) => validerSaisie(),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.edit_note),
                        label: const Text("Valider ce montant"),
                        onPressed: validerSaisie,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Annuler")),
            ],
          );
        },
      ),
    ).whenComplete(ctrl.dispose);
  }

  List<AutreFraisPaiement> _paiementsDuFraisSelectionne() {
    if (selectedFrais == null) return [];
    return widget.fraisScolaires
        .getAutresFraisPaiementsForYear()
        .where((p) => p.autreFraisId == selectedFrais!.id)
        .toList();
  }

  Map<String, double> _totalsByClasseForSelected() {
    final totals = <String, double>{};
    for (final p in _paiementsDuFraisSelectionne()) {
      final eleve = widget.fraisScolaires.trouverEleveParId(p.eleveId);
      final label = eleve != null ? eleve.classe : "Élève(s) introuvable(s)";
      totals[label] = (totals[label] ?? 0) + p.montant;
    }
    return totals;
  }

  Map<String, double> _totalsByOptionForSelected() {
    final totals = <String, double>{};
    for (final p in _paiementsDuFraisSelectionne()) {
      final eleve = widget.fraisScolaires.trouverEleveParId(p.eleveId);
      final label = eleve != null ? eleve.section : "Élève(s) introuvable(s)";
      totals[label] = (totals[label] ?? 0) + p.montant;
    }
    return totals;
  }

  // ⚡ Paiement partiel : un paiement peut couvrir une partie d'une tranche
  // ou plusieurs tranches ; il est ventilé dans l'ordre des tranches.
  Map<String, double> _totalsByTrancheForSelected() {
    final fs = widget.fraisScolaires;
    final frais = selectedFrais!;
    final totals = <String, double>{};
    final Set<String> elevesTraites = {};
    for (final p in _paiementsDuFraisSelectionne()) {
      if (p.trancheNom.trim().isEmpty) {
        totals[_libelleSansTranche] =
            (totals[_libelleSansTranche] ?? 0) + p.montant;
        continue;
      }
      final eleve = fs.trouverEleveParId(p.eleveId);
      final tranches =
      eleve != null ? fs.getTranchesPourEleve(frais, eleve) : null;
      if (eleve == null || tranches == null || tranches.isEmpty) {
        final label = p.trancheNom.trim();
        totals[label] = (totals[label] ?? 0) + p.montant;
        continue;
      }
      if (!elevesTraites.add(eleve.id)) continue;
      final ordonnes = fs.paiementsOrdonnesAutreFrais(eleve, frais);
      final ventilation =
      FraisScolaires.ventilerPaiementsAutreFrais(tranches, ordonnes);
      for (var i = 0; i < ordonnes.length; i++) {
        if (ordonnes[i].trancheNom.trim().isEmpty) continue;
        ventilation[i].forEach((j, montant) {
          final label = tranches[j].nom.trim();
          totals[label] = (totals[label] ?? 0) + montant;
        });
      }
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
    final byTranche = _sortedEntries(_totalsByTrancheForSelected());
    final totalGeneral =
    byClasse.fold<double>(0.0, (sum, e) => sum + e.value);
    final bool afficherTranches =
    byTranche.any((e) => e.key != _libelleSansTranche);

    Widget ligne(MapEntry<String, double> e) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(e.key)),
          Text(
            "${e.value.toStringAsFixed(0)} FC",
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );

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
                  ...byOption.map(ligne),
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
                  ...byClasse.map(ligne),
                if (afficherTranches) ...[
                  const SizedBox(height: 18),
                  const Text(
                    "Par tranche",
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo),
                  ),
                  const SizedBox(height: 6),
                  ...byTranche.map(ligne),
                ],
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

  void _showTranchesDialog() {
    if (selectedFrais == null) return;
    final frais = selectedFrais!;
    final fs = widget.fraisScolaires;

    String? cibleSection =
    frais.scope == 'all' ? filterSection : frais.section;
    String? cibleClasse;
    if (frais.scope == 'classe') {
      cibleClasse = frais.classe;
    } else if (cibleSection != null &&
        filterClasse != null &&
        cibleSection == filterSection) {
      cibleClasse = fs.classeNumeroFromFullClasse(filterClasse!);
    }
    // ⚡ NOUVEAU — mode choisi pour une cible encore vide : false = tranches,
    // true = mois. Dès que la cible a des échéances, le mode est déduit.
    bool modeMoisChoisi = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final List<String> sectionsDispo = frais.scope == 'all'
              ? List<String>.from(fs.config.sections)
              : <String>[if (frais.section != null) frais.section!];

          if (cibleSection != null && !sectionsDispo.contains(cibleSection)) {
            cibleSection = null;
            cibleClasse = null;
          }

          List<String> classesDispo = <String>[];
          if (cibleSection != null) {
            if (frais.scope == 'classe') {
              classesDispo = <String>[if (frais.classe != null) frais.classe!];
            } else {
              classesDispo = fs.getClassesForSection(cibleSection!);
            }
          }
          if (cibleClasse != null && !classesDispo.contains(cibleClasse)) {
            cibleClasse = null;
          }

          final bool sectionVerrouillee = frais.scope != 'all';
          final bool classeVerrouillee = frais.scope == 'classe';

          final String cle = fs.cleTranchePourCible(
            section: cibleSection,
            classeNumero: cibleClasse,
          );
          final List<AutreFraisTranche> tranches =
          fs.getTranchesPourCle(frais, cle);
          final double montantTotalFrais = fs.getMontantAutreFraisPourCible(
            frais,
            section: cibleSection,
            classeNumero: cibleClasse,
          );
          final double sommeTranches =
          tranches.fold(0.0, (sum, t) => sum + t.montant);
          final double resteARepartir = montantTotalFrais - sommeTranches;
          // ⚡ NOUVEAU — paiement par mois pour cette cible ?
          final bool modeMois = tranches.isNotEmpty
              ? fs.cleEstParMois(frais, cle)
              : modeMoisChoisi;
          final bool modeVerrouille = tranches.isNotEmpty;
          final int nbPaiementsCible = fs.compterPaiementsPourCle(frais, cle);
          final String motEcheance = modeMois ? "mois" : "tranches";

          final String cibleLabel = cibleClasse != null
              ? "la classe $cibleClasse ($cibleSection)"
              : (cibleSection != null
              ? "la section $cibleSection"
              : "toute l'école");

          Future<void> rafraichir() async {
            setDialogState(() {});
            if (mounted) setState(() {});
          }

          Future<void> ajouterOuModifier({AutreFraisTranche? existante}) async {
            if (modeMois) {
              final Future<bool?> dialogue = existante == null
                  ? _showAjouterMoisDialog(
                ctx,
                frais: frais,
                cle: cle,
                dejaPresents: tranches.map((t) => t.mois).toList(),
                resteARepartir: resteARepartir,
              )
                  : _showEditMoisDialog(
                ctx,
                frais: frais,
                cle: cle,
                tranche: existante,
                autresMois: tranches
                    .where((t) => t.id != existante.id)
                    .map((t) => t.mois)
                    .toList(),
              );
              final bool? ok = await dialogue;
              if (ok == true) await rafraichir();
              return;
            }
            final bool? ok = await _showEditTrancheDialog(
              ctx,
              frais: frais,
              cle: cle,
              tranche: existante,
              nomSuggere: fs.nomTrancheSuggere(tranches.length + 1),
              montantSuggere: resteARepartir > 0 ? resteARepartir : 0,
            );
            if (ok == true) await rafraichir();
          }

          Future<void> supprimer(AutreFraisTranche t) async {
            final bool? confirme = await showDialog<bool>(
              context: ctx,
              builder: (ctx2) => AlertDialog(
                title: Text(t.estMois
                    ? "Supprimer ce mois ?"
                    : "Supprimer cette tranche ?"),
                content: Text(
                  "Voulez-vous vraiment supprimer \"${t.nom}\" "
                      "(${t.montant.toStringAsFixed(0)} FC) pour $cibleLabel ?",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx2, false),
                    child: const Text("Annuler"),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white),
                    onPressed: () => Navigator.pop(ctx2, true),
                    child: const Text("Supprimer"),
                  ),
                ],
              ),
            );
            if (confirme != true) return;
            final bool supprimee = await fs.deleteTranchePourAutreFrais(
              autreFraisId: frais.id,
              cle: cle,
              trancheId: t.id,
            );
            if (!supprimee && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      "Impossible : des paiements ont déjà été enregistrés "
                          "pour ${t.estMois ? 'ce mois' : 'cette tranche'}."),
                  backgroundColor: Colors.red,
                ),
              );
            }
            await rafraichir();
          }

          Future<void> deplacer(AutreFraisTranche t, int delta) async {
            final bool ok = await fs.deplacerTranchePourAutreFrais(
              autreFraisId: frais.id,
              cle: cle,
              trancheId: t.id,
              delta: delta,
            );
            if (!ok && nbPaiementsCible > 0 && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Impossible de changer l'ordre : des "
                      "paiements sont déjà enregistrés pour cette cible."),
                  backgroundColor: Colors.red,
                ),
              );
            }
            await rafraichir();
          }

          Future<void> copierVersAutresCibles() async {
            final bool? ok = await _showCopierEcheancesDialog(
              ctx,
              frais: frais,
              cleSource: cle,
              libelleSource: cibleLabel,
              modeMois: modeMois,
            );
            if (ok == true) await rafraichir();
          }

          Widget messageCoherence() {
            if (tranches.isEmpty) {
              return Text(
                modeMois
                    ? "Aucun mois pour cette cible : ajoutez les mois à payer, "
                    "dans l'ordre (le premier ajouté est le premier mois à "
                    "payer). Sans mois ni tranche, les élèves concernés "
                    "paient ce frais en une seule fois (sauf si une cible "
                    "plus large a des mois ou des tranches)."
                    : "Aucune tranche pour cette cible : les élèves concernés "
                    "paient ce frais en une seule fois (sauf si une tranche "
                    "existe pour une cible plus large).",
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              );
            }
            if (resteARepartir.abs() < 0.5) {
              return Text(
                "✅ La somme des $motEcheance correspond exactement au "
                    "montant du frais.",
                style: const TextStyle(fontSize: 11, color: Colors.green),
              );
            }
            if (resteARepartir > 0) {
              return Text(
                "⚠️ Il reste ${resteARepartir.toStringAsFixed(0)} FC à "
                    "répartir pour atteindre le montant du frais.",
                style: const TextStyle(fontSize: 11, color: Colors.orange),
              );
            }
            return Text(
              "⚠️ Les $motEcheance dépassent le montant du frais de "
                  "${(-resteARepartir).toStringAsFixed(0)} FC.",
              style: const TextStyle(fontSize: 11, color: Colors.orange),
            );
          }

          return AlertDialog(
            title: Text("Tranches / Mois — ${frais.nom}"),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Choisissez à qui s'appliquent les tranches ou les mois :",
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo),
                    ),
                    const SizedBox(height: 6),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: cibleSection,
                      hint: const Text("Toute l'école"),
                      items: [
                        if (!sectionVerrouillee)
                          const DropdownMenuItem<String>(
                              value: null, child: Text("Toute l'école")),
                        ...sectionsDispo.map((s) =>
                            DropdownMenuItem(value: s, child: Text(s))),
                      ],
                      onChanged: sectionVerrouillee
                          ? null
                          : (v) => setDialogState(() {
                        cibleSection = v;
                        cibleClasse = null;
                      }),
                    ),
                    const SizedBox(height: 4),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: cibleClasse,
                      hint: Text(cibleSection == null
                          ? "Choisissez d'abord une section"
                          : "Toute la section"),
                      items: [
                        if (!classeVerrouillee)
                          const DropdownMenuItem<String>(
                              value: null, child: Text("Toute la section")),
                        ...classesDispo.map((c) =>
                            DropdownMenuItem(value: c, child: Text(c))),
                      ],
                      onChanged: (cibleSection == null || classeVerrouillee)
                          ? null
                          : (v) => setDialogState(() => cibleClasse = v),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Cible : $cibleLabel",
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Montant du frais : "
                                "${montantTotalFrais.toStringAsFixed(0)} FC  |  "
                                "Somme des $motEcheance : "
                                "${sommeTranches.toStringAsFixed(0)} FC",
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ⚡ NOUVEAU — mode de paiement de cette cible.
                    const Text(
                      "Ce frais se paie :",
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          avatar: const Icon(Icons.splitscreen, size: 16),
                          label: const Text("Par tranches"),
                          selected: !modeMois,
                          onSelected: modeVerrouille
                              ? null
                              : (_) =>
                              setDialogState(() => modeMoisChoisi = false),
                        ),
                        ChoiceChip(
                          avatar: const Icon(Icons.calendar_month, size: 16),
                          label: const Text("Selon les mois"),
                          selected: modeMois,
                          onSelected: modeVerrouille
                              ? null
                              : (_) =>
                              setDialogState(() => modeMoisChoisi = true),
                        ),
                      ],
                    ),
                    if (modeVerrouille)
                      Text(
                        modeMois
                            ? "Cette cible se paie par mois. Pour revenir aux "
                            "tranches, supprimez d'abord tous les mois."
                            : "Cette cible se paie par tranches. Pour passer "
                            "aux mois, supprimez d'abord toutes les tranches.",
                        style:
                        const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    const SizedBox(height: 6),
                    messageCoherence(),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            modeMois
                                ? "Mois (ordre de paiement)"
                                : "Tranches",
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => ajouterOuModifier(),
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(
                              modeMois
                                  ? "Ajouter des mois"
                                  : "Ajouter une tranche",
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    if (tranches.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          modeMois
                              ? "Aucun mois ajouté pour cette cible."
                              : "Aucune tranche ajoutée pour cette cible.",
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                      )
                    else
                      ...List.generate(tranches.length, (i) {
                        final t = tranches[i];
                        final int nbPaiements =
                        fs.compterPaiementsPourTranche(t.id);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.estMois
                                          ? "${fs.nomMoisOrdinal(i + 1)} à payer : ${t.mois}"
                                          : "${i + 1}. ${t.nom}",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500),
                                    ),
                                    Text(
                                      "${t.montant.toStringAsFixed(0)} FC"
                                          "${nbPaiements > 0 ? '  •  $nbPaiements paiement(s)' : ''}",
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.indigo,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // ⚡ NOUVEAU — changer l'ordre de paiement.
                              IconButton(
                                icon: const Icon(Icons.arrow_upward,
                                    size: 18),
                                tooltip: "Payer plus tôt",
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 28, minHeight: 32),
                                onPressed: (i == 0 || nbPaiementsCible > 0)
                                    ? null
                                    : () => deplacer(t, -1),
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_downward,
                                    size: 18),
                                tooltip: "Payer plus tard",
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 28, minHeight: 32),
                                onPressed: (i == tranches.length - 1 ||
                                    nbPaiementsCible > 0)
                                    ? null
                                    : () => deplacer(t, 1),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit,
                                    size: 18, color: Colors.indigo),
                                tooltip: "Modifier",
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 32, minHeight: 32),
                                onPressed: () =>
                                    ajouterOuModifier(existante: t),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: Colors.red),
                                tooltip: "Supprimer",
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 32, minHeight: 32),
                                onPressed: () => supprimer(t),
                              ),
                            ],
                          ),
                        );
                      }),
                    if (tranches.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: copierVersAutresCibles,
                          icon: const Icon(Icons.copy_all, size: 16),
                          label: Text(
                            "Appliquer ces $motEcheance à d'autres classes "
                                "ou sections",
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                    if (nbPaiementsCible > 0)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          "Des paiements existent déjà pour cette cible : "
                              "l'ordre de paiement ne peut plus être changé.",
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      "Règle : pour un élève, on applique les tranches (ou les "
                          "mois) de la "
                          "cible la plus précise (classe, puis section, puis "
                          "toute l'école). L'argent déjà versé avant l'ajout "
                          "des tranches est conservé et couvre les premières "
                          "tranches dans l'ordre.",
                      style: TextStyle(fontSize: 11, color: Colors.grey),
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
          );
        },
      ),
    );
  }

  Future<bool?> _showEditTrancheDialog(
      BuildContext ctx, {
        required AutreFrais frais,
        required String cle,
        AutreFraisTranche? tranche,
        required String nomSuggere,
        required double montantSuggere,
      }) {
    final nomCtrl =
    TextEditingController(text: tranche != null ? tranche.nom : nomSuggere);
    final montantCtrl = TextEditingController(
      text: tranche != null
          ? tranche.montant.toStringAsFixed(0)
          : (montantSuggere > 0 ? montantSuggere.toStringAsFixed(0) : ''),
    );
    final bool isEditing = tranche != null;

    return showDialog<bool>(
      context: ctx,
      builder: (ctx2) => AlertDialog(
        title: Text(isEditing ? "Modifier la tranche" : "Nouvelle tranche"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nomCtrl,
              decoration: const InputDecoration(
                labelText: "Nom de la tranche",
                hintText: "Ex: Première tranche",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: montantCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Montant de la tranche (FC)",
                hintText: "Ex: 5000",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx2, false),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () async {
              final nom = nomCtrl.text.trim();
              final montant = double.tryParse(montantCtrl.text
                  .trim()
                  .replaceAll(' ', '')
                  .replaceAll(',', '.'));
              if (nom.isEmpty || montant == null || montant <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                    Text("Veuillez entrer un nom et un montant valides"),
                  ),
                );
                return;
              }
              if (isEditing) {
                await widget.fraisScolaires.updateTranchePourAutreFrais(
                  autreFraisId: frais.id,
                  cle: cle,
                  trancheId: tranche.id,
                  nom: nom,
                  montant: montant,
                );
              } else {
                await widget.fraisScolaires.addTranchePourAutreFrais(
                  autreFraisId: frais.id,
                  cle: cle,
                  nom: nom,
                  montant: montant,
                );
              }
              if (ctx2.mounted) Navigator.pop(ctx2, true);
            },
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // ⚡ NOUVEAU — PAIEMENT PAR MOIS : ajout de mois. Les mois sont pris dans
  // l'ordre où on les coche (1er coché = 1er mois à payer). L'ordre peut
  // ensuite être changé avec les flèches tant qu'aucun paiement n'existe.
  // ==========================================================================
  Future<bool?> _showAjouterMoisDialog(
      BuildContext ctx, {
        required AutreFrais frais,
        required String cle,
        required List<String> dejaPresents,
        required double resteARepartir,
      }) {
    final fs = widget.fraisScolaires;
    final List<String> choisis = [];
    final montantCtrl = TextEditingController();
    final List<String> disponibles = FraisScolaires.moisAutresFraisDisponibles
        .where((m) => !dejaPresents.any((d) => FraisScolaires.memeMois(d, m)))
        .toList();

    return showDialog<bool>(
      context: ctx,
      builder: (ctx2) => StatefulBuilder(
        builder: (ctx2, setD) {
          final int n = choisis.length;
          final double parDefaut =
          (n > 0 && resteARepartir > 0) ? (resteARepartir / n) : 0;
          return AlertDialog(
            title: const Text("Ajouter des mois"),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Cochez les mois dans l'ordre où ils doivent être "
                          "payés (le premier coché est le premier mois à "
                          "payer).",
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    if (disponibles.isEmpty)
                      const Text(
                        "Tous les mois sont déjà ajoutés pour cette cible.",
                        style: TextStyle(color: Colors.grey),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: disponibles.map((m) {
                          final int idx = choisis.indexOf(m);
                          return FilterChip(
                            label: Text(idx >= 0 ? "${idx + 1}. $m" : m),
                            selected: idx >= 0,
                            onSelected: (sel) => setD(() {
                              if (sel) {
                                choisis.add(m);
                              } else {
                                choisis.remove(m);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                    if (disponibles.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        children: [
                          TextButton(
                            onPressed: () => setD(() {
                              choisis
                                ..clear()
                                ..addAll(disponibles.where((m) =>
                                FraisScolaires.rangMoisScolaire(m) <= 9));
                            }),
                            child: const Text("Septembre → Juin",
                                style: TextStyle(fontSize: 12)),
                          ),
                          TextButton(
                            onPressed: () => setD(() {
                              choisis
                                ..clear()
                                ..addAll(disponibles);
                            }),
                            child: const Text("Tous",
                                style: TextStyle(fontSize: 12)),
                          ),
                          TextButton(
                            onPressed: () => setD(choisis.clear),
                            child: const Text("Aucun",
                                style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                    if (choisis.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        "Ordre de paiement : ${List.generate(choisis.length, (i) => '${fs.nomMoisOrdinal(dejaPresents.length + i + 1)} = ${choisis[i]}').join(', ')}",
                        style: const TextStyle(
                            fontSize: 11, color: Colors.indigo),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: montantCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: "Montant à payer pour chaque mois (FC)",
                        hintText: parDefaut > 0
                            ? parDefaut.toStringAsFixed(0)
                            : "Ex: 5000",
                        helperText: parDefaut > 0
                            ? "Vide = ${resteARepartir.toStringAsFixed(0)} FC "
                            "restants répartis à parts égales"
                            : "Chaque mois pourra ensuite être modifié",
                        helperMaxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx2, false),
                child: const Text("Annuler"),
              ),
              ElevatedButton(
                onPressed: choisis.isEmpty
                    ? null
                    : () async {
                  final String txt = montantCtrl.text
                      .trim()
                      .replaceAll(' ', '')
                      .replaceAll(',', '.');
                  final double? montant =
                  txt.isEmpty ? parDefaut : double.tryParse(txt);
                  if (montant == null || montant <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            "Veuillez entrer un montant par mois valide"),
                      ),
                    );
                    return;
                  }
                  try {
                    final int ajoutes = await fs.addMoisPourAutreFrais(
                      autreFraisId: frais.id,
                      cle: cle,
                      mois: List<String>.from(choisis),
                      montantParMois: montant.roundToDouble(),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("✅ $ajoutes mois ajouté(s)"),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                    if (ctx2.mounted) Navigator.pop(ctx2, true);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              e.toString().replaceFirst('Exception: ', '')),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text("Ajouter"),
              ),
            ],
          );
        },
      ),
    );
  }

  // ⚡ NOUVEAU — modifier un mois (changer de mois ou de montant).
  Future<bool?> _showEditMoisDialog(
      BuildContext ctx, {
        required AutreFrais frais,
        required String cle,
        required AutreFraisTranche tranche,
        required List<String> autresMois,
      }) {
    final fs = widget.fraisScolaires;
    final montantCtrl =
    TextEditingController(text: tranche.montant.toStringAsFixed(0));
    final List<String> choix = FraisScolaires.moisAutresFraisDisponibles
        .where((m) =>
    FraisScolaires.memeMois(m, tranche.mois) ||
        !autresMois.any((a) => FraisScolaires.memeMois(a, m)))
        .toList();
    String moisChoisi = choix.firstWhere(
            (m) => FraisScolaires.memeMois(m, tranche.mois),
        orElse: () => tranche.mois);
    if (!choix.contains(moisChoisi)) choix.insert(0, moisChoisi);
    final int nbPaiements = fs.compterPaiementsPourTranche(tranche.id);

    return showDialog<bool>(
      context: ctx,
      builder: (ctx2) => StatefulBuilder(
        builder: (ctx2, setD) => AlertDialog(
          title: const Text("Modifier le mois"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: moisChoisi,
                isExpanded: true,
                decoration: const InputDecoration(labelText: "Mois"),
                items: choix
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: nbPaiements > 0
                    ? null
                    : (v) => setD(() => moisChoisi = v ?? moisChoisi),
              ),
              if (nbPaiements > 0)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    "Des paiements existent pour ce mois : seul le montant "
                        "peut être modifié.",
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: montantCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Montant du mois (FC)",
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2, false),
              child: const Text("Annuler"),
            ),
            ElevatedButton(
              onPressed: () async {
                final montant = double.tryParse(montantCtrl.text
                    .trim()
                    .replaceAll(' ', '')
                    .replaceAll(',', '.'));
                if (montant == null || montant <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Veuillez entrer un montant valide")),
                  );
                  return;
                }
                await fs.updateTranchePourAutreFrais(
                  autreFraisId: frais.id,
                  cle: cle,
                  trancheId: tranche.id,
                  nom: moisChoisi,
                  montant: montant,
                  mois: moisChoisi,
                );
                if (ctx2.mounted) Navigator.pop(ctx2, true);
              },
              child: const Text("Enregistrer"),
            ),
          ],
        ),
      ),
    );
  }

  // ⚡ NOUVEAU — appliquer les mois (ou tranches) d'une cible à d'autres
  // classes / sections : « ces classes de telle section paient ces mois ».
  Future<bool?> _showCopierEcheancesDialog(
      BuildContext ctx, {
        required AutreFrais frais,
        required String cleSource,
        required String libelleSource,
        required bool modeMois,
      }) {
    final fs = widget.fraisScolaires;
    final String mot = modeMois ? "mois" : "tranches";

    // Cibles possibles selon la portée du frais.
    final List<String> cles = [];
    final List<String> sections = frais.scope == 'all'
        ? List<String>.from(fs.config.sections)
        : <String>[if (frais.section != null) frais.section!];
    if (frais.scope == 'all') cles.add(FraisScolaires.kTrancheCleTous);
    if (frais.scope != 'classe') {
      for (final sec in sections) {
        cles.add(fs.cleTrancheSection(sec));
        for (final c in fs.getClassesForSection(sec)) {
          cles.add(fs.cleTrancheClasse(sec, c));
        }
      }
    }
    cles.remove(cleSource);
    final Set<String> coches = {};

    return showDialog<bool>(
      context: ctx,
      builder: (ctx2) => StatefulBuilder(
        builder: (ctx2, setD) => AlertDialog(
          title: Text("Appliquer ces $mot"),
          content: SizedBox(
            width: double.maxFinite,
            child: cles.isEmpty
                ? const Text(
                "Ce frais ne concerne qu'une seule classe : aucune autre "
                    "cible possible.")
                : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Les $mot de $libelleSource seront copiés (même ordre, "
                      "mêmes montants) vers les classes / sections cochées. "
                      "Une cible qui a déjà des $mot ou des tranches sera "
                      "remplacée, sauf si des paiements y sont déjà "
                      "enregistrés.",
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: cles.map((cle) {
                      final existantes = fs.getTranchesPourCle(frais, cle);
                      final int nbP = fs.compterPaiementsPourCle(frais, cle);
                      final bool estClasse = cle.startsWith('C:');
                      String? sousTitre;
                      if (nbP > 0) {
                        sousTitre = "Paiements déjà enregistrés : non "
                            "modifiable";
                      } else if (existantes.isNotEmpty) {
                        sousTitre = fs.cleEstParMois(frais, cle)
                            ? "A déjà ${existantes.length} mois (sera "
                            "remplacé)"
                            : "A déjà ${existantes.length} tranche(s) "
                            "(sera remplacé)";
                      }
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.only(
                            left: estClasse ? 24 : 0),
                        value: coches.contains(cle),
                        title: Text(fs.libelleCleTranche(cle)),
                        subtitle: sousTitre == null
                            ? null
                            : Text(sousTitre,
                            style: const TextStyle(fontSize: 11)),
                        onChanged: nbP > 0
                            ? null
                            : (v) => setD(() {
                          if (v == true) {
                            coches.add(cle);
                          } else {
                            coches.remove(cle);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2, false),
              child: const Text("Annuler"),
            ),
            if (cles.isNotEmpty)
              ElevatedButton(
                onPressed: coches.isEmpty
                    ? null
                    : () async {
                  final res = await fs.copierTranchesVersCibles(
                    autreFraisId: frais.id,
                    cleSource: cleSource,
                    clesCibles: coches.toList(),
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "✅ $mot appliqués à ${res.copiees} cible(s)"
                              "${res.ignorees.isNotEmpty ? ' — ${res.ignorees.length} ignorée(s) (paiements existants)' : ''}",
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                  if (ctx2.mounted) Navigator.pop(ctx2, true);
                },
                child: const Text("Appliquer"),
              ),
          ],
        ),
      ),
    );
  }

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

          final String filtreLabel =
          (filterSection == null && filterClasse == null)
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
                          padding: const EdgeInsets.symmetric(vertical: 3),
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
                                onPressed: () =>
                                    confirmDeleteAdmin(admin.id, admin.nom),
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

    final classesOptionsForFilter = filterSection != null
        ? widget.fraisScolaires.getAllDisplayClassesForSection(filterSection!)
        : <String>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Autres Frais de Paiement"),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: "Totaux par classe, option et tranche",
            onPressed: selectedFrais == null ? null : _showTotalsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.splitscreen),
            tooltip: "Tranches / mois du frais",
            onPressed: selectedFrais == null ? null : _showTranchesDialog,
          ),
          IconButton(
            icon: const Icon(Icons.account_balance),
            tooltip: "Administrations (Autres Frais)",
            onPressed:
            selectedFrais == null ? null : _showAdminRepartitionDialog,
          ),
          IconButton(
            icon: const Icon(Icons.fact_check),
            tooltip: "Recouvrement par tranche / mois",
            onPressed: selectedFrais == null ? null : _ouvrirRecouvrement,
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
                    final hasTranches = f.tranchesParCle.values
                        .any((liste) => liste.isNotEmpty);
                    return DropdownMenuItem(
                      value: f,
                      child: Text(
                          "${f.nom} — ${f.montant.toStringAsFixed(0)} FC (${_scopeLabel(f)})"
                              "${hasExceptions ? ' • montants variables' : ''}"
                              "${hasTranches ? ' • par tranches' : ''}"),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedFrais = value;
                      selectedStudentIds.clear();
                      filterSection = null;
                      filterClasse = null;
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
                            filterClasse = null;
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
                            ...classesOptionsForFilter.map((c) =>
                                DropdownMenuItem(
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
                        onPressed: _showTranchesDialog,
                        icon: const Icon(Icons.splitscreen, size: 18),
                        label: const Text("Tranches / Mois",
                            style: TextStyle(fontSize: 12)),
                      ),
                      TextButton.icon(
                        onPressed: _showAdminRepartitionDialog,
                        icon: const Icon(Icons.account_balance, size: 18),
                        label: const Text("Administrations & Répartition",
                            style: TextStyle(fontSize: 12)),
                      ),
                      TextButton.icon(
                        onPressed: _ouvrirRecouvrement,
                        icon: const Icon(Icons.fact_check, size: 18),
                        label: const Text("Recouvrement par tranche / mois",
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
                  final fs = widget.fraisScolaires;
                  final statut =
                  fs.getStatutAutreFrais(selectedFrais!, eleve);
                  final bool dejaPaye = statut.solde;
                  final bool partiel = statut.partiel;
                  final isSelected = selectedStudentIds.contains(eleve.id);
                  final double montantEleve = fs
                      .getMontantAutreFraisPourEleve(selectedFrais!, eleve);
                  final prochaine = statut.prochaine;

                  String ligneTranches = '';
                  if (statut.tranches.isNotEmpty) {
                    ligneTranches =
                    'Tranches : ${statut.nbPayees}/${statut.tranches.length} payée(s)\n'
                        '${_libelleEtatsTranches(statut)}';
                  }
                  String ligneVerse = '';
                  if (statut.totalPaye > 0 || statut.tranches.isNotEmpty) {
                    ligneVerse =
                    'Dû : ${_fc(statut.totalDu)} | Payé : ${_fc(statut.totalPaye)} '
                        '| Reste : ${_fc(statut.reste)}';
                  }

                  return Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => _enregistrerTap(eleve),
                    child: Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      color: dejaPaye
                          ? Colors.green.withAlpha(20)
                          : (partiel ? Colors.orange.withAlpha(25) : null),
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
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ID: ${eleve.id} | Classe: ${eleve.classe} (${eleve.section}) | '
                                  'Montant: ${montantEleve.toStringAsFixed(0)} FC',
                            ),
                            if (ligneTranches.isNotEmpty)
                              Text(
                                ligneTranches,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: dejaPaye
                                      ? Colors.green
                                      : Colors.indigo,
                                ),
                              ),
                            if (ligneVerse.isNotEmpty)
                              Text(
                                ligneVerse,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                          ],
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
                          tooltip: prochaine != null
                              ? "Payer : ${prochaine.nom}"
                              : "Payer",
                          onPressed: _processing
                              ? null
                              : () => _confirmPaiementUnique(eleve),
                        ),
                        onTap:
                        dejaPaye ? null : () => _toggleStudent(eleve),
                      ),
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
                  "ajouter (ex: Frais de l'État, Frais d'Aide...). Les "
                  "tranches se configurent ensuite directement ici, avec "
                  "le bouton \"Tranches\".",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}