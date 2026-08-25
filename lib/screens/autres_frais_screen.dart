import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../frais_scolaires.dart';
import '../models.dart';
import '../services/epson_printer_service.dart';

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

  @override
  void initState() {
    super.initState();
    final frais = widget.fraisScolaires.getAutresFrais();
    if (frais.isNotEmpty) selectedFrais = frais.first;
    searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<Eleve> get _eligibleFiltered {
    if (selectedFrais == null) return [];
    final query = searchController.text.toLowerCase().trim();
    final eligible =
    widget.fraisScolaires.getEligibleStudentsForAutreFrais(selectedFrais!);
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

  Future<void> _imprimerRecu(Eleve eleve, AutreFrais frais) async {
    final prefs = await SharedPreferences.getInstance();
    final printerName = prefs.getString('printer_name') ?? '';
    if (printerName.isEmpty) return;
    await EscPosPrinterService.printAutreFraisReceipt(
      printerName: printerName,
      schoolName: widget.fraisScolaires.config.schoolName,
      titreFrais: frais.nom,
      studentName: '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      classe: eleve.classe,
      section: eleve.section,
      montant: frais.montant,
    );
  }

  Future<void> _payerUnSeul(Eleve eleve) async {
    if (selectedFrais == null) return;
    if (widget.fraisScolaires.hasPaidAutreFrais(eleve, selectedFrais!)) return;
    setState(() => _processing = true);
    final frais = selectedFrais!;
    await widget.fraisScolaires.payAutreFrais(frais: frais, eleve: eleve);
    await _imprimerRecu(eleve, frais);
    if (mounted) {
      setState(() {
        selectedStudentIds.remove(eleve.id);
        _processing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                "✅ ${frais.nom} enregistré pour ${eleve.nom} ${eleve.prenom}")),
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
    for (final eleve in students) {
      if (widget.fraisScolaires.hasPaidAutreFrais(eleve, frais)) continue;
      await widget.fraisScolaires.payAutreFrais(frais: frais, eleve: eleve);
      success++;
      await _imprimerRecu(eleve, frais);
    }

    if (mounted) {
      setState(() {
        selectedStudentIds.clear();
        _processing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
            Text("✅ Paiement de \"${frais.nom}\" enregistré pour $success élève(s)")),
      );
    }
  }

  void _confirmPaiementUnique(Eleve eleve) {
    if (selectedFrais == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(selectedFrais!.nom),
        content: Text(
          "Confirmer le paiement de "
              "${selectedFrais!.montant.toStringAsFixed(0)} FC pour "
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
  // ⚡ NOUVEAU — RÉIMPRESSION MANUELLE (reçus perdus / mémoire d'impression
  // perdue si l'ordinateur s'éteint avant que l'imprimante ne soit
  // rebranchée).
  //
  // Contrairement à `_imprimerRecu` (impression AUTOMATIQUE d'un seul
  // frais juste après son paiement, inchangée ci-dessus), ce qui suit
  // permet de réimprimer à tout moment :
  //   1. Le reçu d'un seul "autre frais" déjà payé par un élève
  //      (bouton d'impression directement sur sa ligne "Payé").
  //   2. Un reçu REGROUPANT plusieurs "autres frais" DIFFÉRENTS payés
  //      par le MÊME élève (ex: "Frais de l'État" + "Frais d'Aide"),
  //      en UN SEUL reçu — via le bouton "Réimprimer un reçu" de
  //      l'AppBar, qui permet de choisir l'élève puis les frais à
  //      inclure.
  // ==========================================================================

  // ⚡ NOUVEAU — même logique que dans les autres écrans : recharge le
  // logo depuis le disque à chaque impression, pour toujours utiliser
  // la version la plus récente choisie dans les Paramètres.
  Future<Uint8List?> _loadLogoBytesFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasLogo = prefs.getBool('has_logo') ?? false;
      if (!hasLogo) return null;

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/school_logo.png');
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _requirePrinterName() async {
    final prefs = await SharedPreferences.getInstance();
    final printerName = prefs.getString('printer_name') ?? '';
    if (printerName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Aucune imprimante configurée. Allez dans Paramètres pour en choisir une."),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
    return printerName;
  }

  /// Imprime UN SEUL reçu regroupant les `paiements` fournis (un seul, une
  /// sélection, ou tous les "autres frais" déjà réglés) pour `eleve`.
  Future<void> _printAutresFraisReceipt(
      Eleve eleve, List<Map<String, dynamic>> paiements) async {
    if (paiements.isEmpty) return;
    final printerName = await _requirePrinterName();
    if (printerName == null) return;

    final logoBytes = await _loadLogoBytesFromDisk();

    final bool ok =
    await EscPosPrinterService.printAutresFraisTransactionsReceipt(
      printerName: printerName,
      schoolName: widget.fraisScolaires.config.schoolName,
      studentName: '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      classe: eleve.classe,
      section: eleve.section,
      paiements: paiements,
      logoBytes: logoBytes,
      duplicata: true,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? "🖨️ Reçu réimprimé avec succès"
              : "⚠️ Impression impossible — vérifiez l'imprimante"),
          backgroundColor: ok ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  /// Réimprime le reçu d'un seul paiement déjà effectué par `eleve` pour
  /// le frais actuellement sélectionné (`selectedFrais`).
  void _reprintSinglePaiement(Eleve eleve) {
    if (selectedFrais == null) return;
    final paiements = widget.fraisScolaires
        .getAutresFraisPaiementsForYear()
        .where((p) =>
    p.autreFraisId == selectedFrais!.id && p.eleveId == eleve.id)
        .toList();
    if (paiements.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Paiement introuvable.")),
      );
      return;
    }
    final p = paiements.first;
    _printAutresFraisReceipt(eleve, [
      {
        'nom': p.autreFraisNom,
        'montant': p.montant,
        'date': p.dateFormatee,
      }
    ]);
  }

  /// ⚡ NOUVEAU — Dialogue "Réimprimer un reçu" (AppBar) : permet de
  /// rechercher un élève puis de voir TOUS les "autres frais" qu'il a
  /// déjà payés (tous types confondus, pas seulement le frais
  /// actuellement sélectionné dans l'écran), pour en sélectionner un ou
  /// plusieurs et générer un seul reçu regroupé.
  void _showStudentReprintDialog() {
    final allPaiements = widget.fraisScolaires.getAutresFraisPaiementsForYear();
    if (allPaiements.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Aucun paiement d'autre frais enregistré.")),
      );
      return;
    }

    // Regroupement par élève.
    final Map<String, List<AutreFraisPaiement>> byStudent = {};
    for (final p in allPaiements) {
      byStudent.putIfAbsent(p.eleveId, () => []).add(p);
    }

    final searchCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          final query = searchCtrl.text.toLowerCase().trim();
          final entries = byStudent.entries.where((entry) {
            final matches = widget.fraisScolaires.currentData.eleves
                .where((e) => e.id == entry.key)
                .toList();
            if (matches.isEmpty) return query.isEmpty;
            final e = matches.first;
            final name = '${e.nom} ${e.postNom} ${e.prenom}'.toLowerCase();
            return query.isEmpty ||
                name.contains(query) ||
                e.id.toLowerCase().contains(query);
          }).toList();

          return AlertDialog(
            title: const Text("Réimprimer un reçu — Autres frais"),
            content: SizedBox(
              width: double.maxFinite,
              height: 440,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      labelText: "Rechercher un élève",
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setStateDialog(() {}),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: entries.isEmpty
                        ? const Center(child: Text("Aucun élève trouvé."))
                        : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final eleveId = entries[index].key;
                        final paiements = entries[index].value;
                        final matches = widget.fraisScolaires
                            .currentData.eleves
                            .where((e) => e.id == eleveId)
                            .toList();
                        final eleve =
                        matches.isNotEmpty ? matches.first : null;
                        final label = eleve != null
                            ? '${eleve.nom} ${eleve.postNom} ${eleve.prenom}'
                            : "Élève introuvable ($eleveId)";
                        return ListTile(
                          leading: const Icon(Icons.person,
                              color: Colors.indigo),
                          title: Text(label),
                          subtitle:
                          Text("${paiements.length} frais payé(s)"),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: eleve == null
                              ? null
                              : () {
                            Navigator.pop(ctx);
                            _showSelectPaiementsDialog(eleve, paiements);
                          },
                        );
                      },
                    ),
                  ),
                ],
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

  /// ⚡ NOUVEAU — Sélection, pour un élève donné, des paiements d'autres
  /// frais (tous types confondus) à inclure dans le reçu réimprimé.
  void _showSelectPaiementsDialog(
      Eleve eleve, List<AutreFraisPaiement> paiements) {
    final Set<int> selected = {
      for (int i = 0; i < paiements.length; i++) i
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          final allSelected = selected.length == paiements.length;
          return AlertDialog(
            title: Text("${eleve.nom} ${eleve.prenom} — Autres frais"),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: Icon(
                          allSelected ? Icons.deselect : Icons.select_all,
                          size: 16),
                      label: Text(
                        allSelected
                            ? "Tout désélectionner"
                            : "Tout sélectionner",
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () {
                        setStateDialog(() {
                          if (allSelected) {
                            selected.clear();
                          } else {
                            selected
                              ..clear()
                              ..addAll(
                                  List.generate(paiements.length, (i) => i));
                          }
                        });
                      },
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: paiements.length,
                      itemBuilder: (context, i) {
                        final p = paiements[i];
                        return CheckboxListTile(
                          dense: true,
                          value: selected.contains(i),
                          onChanged: (val) {
                            setStateDialog(() {
                              if (val == true) {
                                selected.add(i);
                              } else {
                                selected.remove(i);
                              }
                            });
                          },
                          title: Text(
                              "${p.autreFraisNom} — ${p.montant.toStringAsFixed(0)} FC"),
                          subtitle: Text(p.dateFormatee,
                              style: const TextStyle(fontSize: 11)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Fermer"),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.print),
                label: Text("Imprimer (${selected.length})"),
                onPressed: selected.isEmpty
                    ? null
                    : () {
                  Navigator.pop(ctx);
                  final chosen = selected.toList()..sort();
                  final list = chosen
                      .map((i) => {
                    'nom': paiements[i].autreFraisNom,
                    'montant': paiements[i].montant,
                    'date': paiements[i].dateFormatee,
                  })
                      .toList();
                  _printAutresFraisReceipt(eleve, list);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // ==========================================================================
  // ⚡ NOUVEAU — TOTAUX PAR CLASSE ET PAR OPTION (SECTION) POUR LE FRAIS
  // SÉLECTIONNÉ.
  //
  // On repart des paiements déjà enregistrés (getAutresFraisPaiementsForYear)
  // filtrés sur le frais actuellement sélectionné, puis on retrouve
  // l'élève correspondant (dans l'année en cours) pour connaître sa
  // classe et son option (section) au moment de l'affichage. Si l'élève
  // n'est plus dans `currentData` (cas rare : élève supprimé/déplacé
  // depuis), le paiement est comptabilisé sous "Élève(s) introuvable(s)"
  // pour ne perdre aucun montant dans le total.
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

  @override
  Widget build(BuildContext context) {
    final fraisList = widget.fraisScolaires.getAutresFrais();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Autres Frais de Paiement"),
        actions: [
          // ⚡ NOUVEAU — réimpression manuelle : recherche un élève et
          // permet de réimprimer un reçu regroupant un ou plusieurs de
          // ses "autres frais" déjà payés (même de types différents).
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: "Réimprimer un reçu (élève)",
            onPressed: _showStudentReprintDialog,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: "Totaux par classe et par option",
            onPressed: selectedFrais == null ? null : _showTotalsDialog,
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
                  items: fraisList
                      .map(
                        (f) => DropdownMenuItem(
                      value: f,
                      child: Text(
                          "${f.nom} — ${f.montant.toStringAsFixed(0)} FC (${_scopeLabel(f)})"),
                    ),
                  )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedFrais = value;
                      selectedStudentIds.clear();
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
              ],
            ),
          ),
          if (selectedFrais != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "${_eligibleFiltered.length} élève(s) concerné(s) — cochez "
                          "ceux qui payent, ou utilisez le bouton paiement direct.",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _showTotalsDialog,
                    icon: const Icon(Icons.bar_chart, size: 18),
                    label: const Text("Voir les totaux",
                        style: TextStyle(fontSize: 12)),
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
                        'ID: ${eleve.id} | Classe: ${eleve.classe} (${eleve.section})',
                      ),
                      // ⚡ NOUVEAU — un élève déjà payé affiche désormais
                      // "Payé" ET un bouton d'impression pour réimprimer
                      // son reçu à tout moment (reçu perdu, etc.).
                      trailing: dejaPaye
                          ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "Payé",
                            style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.print,
                                color: Colors.teal, size: 20),
                            tooltip: "Réimprimer ce reçu",
                            onPressed: () =>
                                _reprintSinglePaiement(eleve),
                          ),
                        ],
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