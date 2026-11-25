import 'package:flutter/material.dart';
import '../frais_scolaires.dart';

// ============================================================================
// ⚡ NOUVEAU — RECOUVREMENT PAR TRANCHE (Autres Frais)
// Pour un frais et une tranche (ou le frais entier), deux listes filtrables
// par section et classe : « Ont payé cette tranche » et « N'ont pas encore
// payé cette tranche », chacune exportable en PDF.
// ============================================================================
class RecouvrementAutresFraisScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  final AutreFrais frais;
  final String? sectionInitiale;
  final String? classeInitiale;
  // ⚡ NOUVEAU — ouvrir directement sur un mois (paiement par mois).
  final String? moisInitial;

  const RecouvrementAutresFraisScreen({
    super.key,
    required this.fraisScolaires,
    required this.frais,
    this.sectionInitiale,
    this.classeInitiale,
    this.moisInitial,
  });

  @override
  State<RecouvrementAutresFraisScreen> createState() =>
      _RecouvrementAutresFraisScreenState();
}

class _RecouvrementAutresFraisScreenState
    extends State<RecouvrementAutresFraisScreen> {
  late int _numeroTranche;
  // ⚡ NOUVEAU — mois choisi (null = liste par tranche / frais entier).
  String? _mois;
  String? _section;
  String? _classe;
  bool _generation = false;

  FraisScolaires get fs => widget.fraisScolaires;

  static String _fc(double v) => "${v.toStringAsFixed(0)} FC";

  @override
  void initState() {
    super.initState();
    final moisDispo = fs.moisDefinisAutreFrais(widget.frais);
    final bool queDesMois = widget.frais.tranchesParCle.values
        .every((l) => l.every((t) => t.estMois));
    _numeroTranche = (!queDesMois &&
        fs.nombreMaxTranchesAutreFrais(widget.frais) > 0)
        ? 1
        : 0;
    if (widget.moisInitial != null &&
        moisDispo.any((m) => FraisScolaires.memeMois(m, widget.moisInitial!))) {
      _mois = moisDispo.firstWhere(
              (m) => FraisScolaires.memeMois(m, widget.moisInitial!));
    } else if (queDesMois && moisDispo.isNotEmpty) {
      _mois = moisDispo.first;
    }
    _section = widget.sectionInitiale;
    _classe = widget.sectionInitiale != null ? widget.classeInitiale : null;
  }

  // Libellé d'une tranche par numéro : les noms peuvent différer d'une
  // classe à l'autre, on les affiche tous.
  String _libelleTranche(int n) {
    if (n <= 0) return "Frais entier";
    final noms = <String>{};
    for (final liste in widget.frais.tranchesParCle.values) {
      if (liste.any((t) => t.estMois)) continue;
      if (liste.length >= n && liste[n - 1].nom.trim().isNotEmpty) {
        noms.add(liste[n - 1].nom.trim());
      }
    }
    if (noms.isEmpty) return "Tranche $n";
    return "Tranche $n — ${noms.join(' / ')}";
  }

  Future<void> _genererPdf(bool payes) async {
    setState(() => _generation = true);
    final res = await fs.generateRecouvrementAutreFraisPdf(
      frais: widget.frais,
      numeroTranche: _numeroTranche,
      payes: payes,
      sectionFilter: _section,
      classFilter: _classe,
      mois: _mois,
    );
    if (!mounted) return;
    setState(() => _generation = false);
    final bool ok = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? "✅ PDF enregistré : ${res['path']}"
            : "❌ ${res['error'] ?? 'Erreur lors de la génération du PDF'}"),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  Widget _liste(List<AutreFraisRecouvrementLigne> lignes, bool payes) {
    if (lignes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            payes
                ? "Aucun élève n'a encore payé ${_mois != null ? 'ce mois' : 'cette tranche'} pour ce filtre."
                : "Tous les élèves de ce filtre ont payé ${_mois != null ? 'ce mois' : 'cette tranche'}. 🎉",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    final double totDu = lignes.fold(0.0, (s, l) => s + l.montantDu);
    final double totPaye = lignes.fold(0.0, (s, l) => s + l.montantPaye);
    final double totReste = lignes.fold(0.0, (s, l) => s + l.reste);
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: lignes.length,
            itemBuilder: (context, i) {
              final l = lignes[i];
              final e = l.eleve;
              return Card(
                margin:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                color: payes
                    ? Colors.green.withAlpha(20)
                    : (l.partiel ? Colors.orange.withAlpha(25) : null),
                child: ListTile(
                  dense: true,
                  title: Text('${e.nom} ${e.postNom} ${e.prenom}'),
                  subtitle: Text(
                    "${e.section} — ${e.classe}\n"
                        "Dû : ${_fc(l.montantDu)} | Payé : ${_fc(l.montantPaye)}"
                        " | Reste : ${_fc(l.reste)}",
                  ),
                  trailing: payes
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : (l.partiel
                      ? Chip(
                    label: Text("partiel\n${_fc(l.montantPaye)}",
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11)),
                    backgroundColor: Colors.orange.withAlpha(60),
                  )
                      : null),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.indigo.withAlpha(15),
              border: Border(top: BorderSide(color: Colors.indigo.shade100)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "${lignes.length} élève(s) — Dû : ${_fc(totDu)} | "
                      "Payé : ${_fc(totPaye)} | Reste : ${_fc(totReste)}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: _generation
                      ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.picture_as_pdf),
                  label: const Text("Générer le PDF"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _generation ? null : () => _genererPdf(payes),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final int nbTranches = fs.nombreMaxTranchesAutreFrais(widget.frais);
    final List<String> moisDispo = fs.moisDefinisAutreFrais(widget.frais);
    final bool aDesTranchesClassiques = widget.frais.tranchesParCle.values
        .any((l) => l.any((t) => !t.estMois));
    final rec = _mois != null
        ? fs.recouvrementAutreFraisParMois(
      widget.frais,
      _mois!,
      section: _section,
      classe: _classe,
    )
        : fs.recouvrementAutreFrais(
      widget.frais,
      _numeroTranche,
      section: _section,
      classe: _classe,
    );
    // Valeur du choix : 'M:<mois>' pour un mois, 'T:<n>' pour une tranche
    // (T:0 = frais entier).
    final String choix = _mois != null ? 'M:$_mois' : 'T:$_numeroTranche';
    final classes = _section != null
        ? fs.getAllDisplayClassesForSection(_section!)
        : <String>[];

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text("Recouvrement — ${widget.frais.nom}"),
          bottom: TabBar(
            tabs: [
              Tab(text: "Ont payé (${rec.payes.length})"),
              Tab(text: "N'ont pas payé (${rec.nonPayes.length})"),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey(choix),
                    initialValue: choix,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: moisDispo.isNotEmpty
                          ? "Mois ou tranche"
                          : "Tranche",
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      ...moisDispo.map((m) => DropdownMenuItem(
                          value: 'M:$m', child: Text("Mois de $m"))),
                      if (aDesTranchesClassiques)
                        for (var n = 1; n <= nbTranches; n++)
                          DropdownMenuItem(
                              value: 'T:$n',
                              child: Text(_libelleTranche(n))),
                      const DropdownMenuItem(
                          value: 'T:0', child: Text("Frais entier")),
                    ],
                    onChanged: (v) => setState(() {
                      final String val = v ?? 'T:0';
                      if (val.startsWith('M:')) {
                        _mois = val.substring(2);
                        _numeroTranche = 0;
                      } else {
                        _mois = null;
                        _numeroTranche = int.tryParse(val.substring(2)) ?? 0;
                      }
                    }),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _section,
                          hint: const Text("Toutes les sections"),
                          items: [
                            const DropdownMenuItem<String>(
                                value: null,
                                child: Text("Toutes les sections")),
                            ...fs.config.sections.map((s) =>
                                DropdownMenuItem(value: s, child: Text(s))),
                          ],
                          onChanged: (v) => setState(() {
                            _section = v;
                            _classe = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: classes.contains(_classe) ? _classe : null,
                          hint: const Text("Toutes les classes"),
                          items: [
                            const DropdownMenuItem<String>(
                                value: null,
                                child: Text("Toutes les classes")),
                            ...classes.map((c) =>
                                DropdownMenuItem(value: c, child: Text(c))),
                          ],
                          onChanged: _section == null
                              ? null
                              : (v) => setState(() => _classe = v),
                        ),
                      ),
                    ],
                  ),
                  if (_mois != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        "Seuls les élèves dont la classe ou la section doit "
                            "payer ce mois sont listés. Un mois est payé quand "
                            "les mois précédents (dans l'ordre de paiement) "
                            "le sont aussi.",
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    )
                  else if (_numeroTranche > 0)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        "Seuls les élèves qui ont cette tranche dans leur "
                            "classe ou section sont listés.",
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _liste(rec.payes, true),
                  _liste(rec.nonPayes, false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
