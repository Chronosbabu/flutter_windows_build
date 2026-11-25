import 'package:flutter/material.dart';
import '../frais_scolaires.dart';

// ============================================================================
// ⚡ NOUVEAU — DÉPENSES PAR RUBRIQUE ET PAR MOIS (fenêtre Répartition)
// ----------------------------------------------------------------------------
// Onglet « Un mois » : on choisit un mois (ou toute l'année) et, si on veut,
// une rubrique : on voit pour chaque rubrique sa part collectée, ce qui est
// déjà dépensé, les entrées d'argent et le reste, avec le détail des
// dépenses.
// Onglet « Mois par mois » : tableau rubriques × mois de l'argent déjà
// dépensé ; un appui sur une case montre les dépenses correspondantes.
// Les chiffres viennent des mêmes calculs que le rapport PDF des dépenses
// (mois d'imputation, retenues et entrées compris).
// ============================================================================
class DepensesRubriqueMoisScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;

  const DepensesRubriqueMoisScreen({super.key, required this.fraisScolaires});

  @override
  State<DepensesRubriqueMoisScreen> createState() =>
      _DepensesRubriqueMoisScreenState();
}

class _DepensesRubriqueMoisScreenState
    extends State<DepensesRubriqueMoisScreen>
    with SingleTickerProviderStateMixin {
  static const String _annee = '__ANNEE__';

  late final TabController _tabs;
  late String _mois;
  String? _rubrique; // null = toutes les rubriques
  String? _section; // null = toute l'école

  FraisScolaires get fs => widget.fraisScolaires;

  static String _fc(double v) => "${formatMontant(v)} FC";

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    final courant = fs.currentSchoolMonthName;
    _mois = (courant != null && fs.months.contains(courant))
        ? courant
        : fs.months.first;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  DepensePeriodeStats _stats(String mois) => mois == _annee
      ? fs.depensesStatsAnnee(sectionFilter: _section)
      : fs.depensesStatsPourMois(mois, sectionFilter: _section);

  // Rubriques dans l'ordre : administrations des paramètres, puis les
  // autres rubriques qui ont des mouvements.
  List<RubriqueStat> _rubriquesOrdonnees(DepensePeriodeStats s) {
    final ordre = fs.config.administrations
        .map((a) => a.nom.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    final liste = s.rubriques
        .where((r) =>
            ordre.contains(r.rubrique) || r.total != 0 || r.totalEntrees != 0)
        .toList();
    int rang(RubriqueStat r) {
      final i = ordre.indexOf(r.rubrique);
      return i < 0 ? 1 << 20 : i;
    }

    liste.sort((a, b) {
      final c = rang(a).compareTo(rang(b));
      return c != 0 ? c : a.rubrique.compareTo(b.rubrique);
    });
    return liste;
  }

  // Toutes les rubriques connues sur l'année (pour le filtre et le tableau).
  List<String> _toutesRubriques() =>
      _rubriquesOrdonnees(fs.depensesStatsAnnee(sectionFilter: _section))
          .map((r) => r.rubrique)
          .toList();

  List<Depense> _depensesDe(DepensePeriodeStats s, String rubrique) => s
      .depenses
      .where((d) =>
          d.rubriqueAffichee == rubrique &&
          fs.montantDepensePourFiltre(d, _section) != 0)
      .toList();

  String _libelleMois(String m) => m == _annee ? "Toute l'année" : m;

  // --------------------------------------------------------------------------
  // Filtres communs
  // --------------------------------------------------------------------------
  Widget _filtreSection() {
    return DropdownButtonFormField<String?>(
      key: ValueKey('section_$_section'),
      initialValue: _section,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: "Section",
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem<String?>(
            value: null, child: Text("Toute l'école")),
        ...fs.config.sections.map(
            (s) => DropdownMenuItem<String?>(value: s, child: Text(s))),
      ],
      onChanged: (v) => setState(() => _section = v),
    );
  }

  // --------------------------------------------------------------------------
  // Onglet 1 : un mois
  // --------------------------------------------------------------------------
  Widget _ongletUnMois() {
    final stats = _stats(_mois);
    final rubriquesConnues = _toutesRubriques();
    if (_rubrique != null && !rubriquesConnues.contains(_rubrique)) {
      _rubrique = null;
    }
    var rubriques = _rubriquesOrdonnees(stats);
    if (_rubrique != null) {
      rubriques = rubriques.where((r) => r.rubrique == _rubrique).toList();
      if (rubriques.isEmpty) {
        rubriques = [
          RubriqueStat(rubrique: _rubrique!, pourcentage: 0, collecte: 0)
        ];
      }
    }

    final double depense = rubriques.fold(0.0, (a, r) => a + r.total);
    final double collecte = rubriques.fold(0.0, (a, r) => a + r.collecte);
    final double entrees = rubriques.fold(0.0, (a, r) => a + r.totalEntrees);
    final double reste = rubriques.fold(0.0, (a, r) => a + r.reste);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _filtreSection(),
        const SizedBox(height: 10),
        const Text("Mois",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            ...fs.months.map((m) => ChoiceChip(
                  label: Text(m),
                  selected: _mois == m,
                  onSelected: (_) => setState(() => _mois = m),
                )),
            ChoiceChip(
              label: const Text("Toute l'année"),
              selected: _mois == _annee,
              onSelected: (_) => setState(() => _mois = _annee),
            ),
          ],
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(
          key: ValueKey('rubrique_$_rubrique'),
          initialValue: _rubrique,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: "Rubrique",
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem<String?>(
                value: null, child: Text("Toutes les rubriques")),
            ...rubriquesConnues.map(
                (r) => DropdownMenuItem<String?>(value: r, child: Text(r))),
          ],
          onChanged: (v) => setState(() => _rubrique = v),
        ),
        const SizedBox(height: 12),
        Card(
          color: Colors.indigo.withAlpha(15),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${_libelleMois(_mois)} — "
                  "${_rubrique ?? 'toutes les rubriques'}"
                  "${_section != null ? ' — $_section' : ''}",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.indigo),
                ),
                const SizedBox(height: 6),
                _ligne("Part collectée (après retenues)", collecte,
                    Colors.green.shade700),
                _ligne("Déjà dépensé", -depense, Colors.red),
                if (entrees != 0)
                  _ligne("Entrées d'argent", entrees, Colors.teal),
                const Divider(height: 14),
                _ligne("Reste", reste, Colors.indigo, gras: true),
              ],
            ),
          ),
        ),
        if (_section != null)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              "Avec une section choisie, les dépenses globales (toute "
              "l'école) ne sont pas comptées ; les dépenses indépendantes ou "
              "mixtes sont comptées pour la part de cette section.",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        const SizedBox(height: 8),
        ...rubriques.map((r) => _carteRubrique(stats, r)),
      ],
    );
  }

  Widget _ligne(String label, double v, Color c, {bool gras = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(
            v < 0 ? "- ${_fc(-v)}" : _fc(v),
            style: TextStyle(
              fontSize: 13,
              color: c,
              fontWeight: gras ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteRubrique(DepensePeriodeStats stats, RubriqueStat r) {
    final deps = _depensesDe(stats, r.rubrique);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text(
          r.pourcentage > 0
              ? "${r.rubrique} (${r.pourcentage.toStringAsFixed(r.pourcentage % 1 == 0 ? 0 : 1)} %)"
              : r.rubrique,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          "Dépensé : ${_fc(r.total)}  •  Reste : ${_fc(r.reste)}",
          style: TextStyle(
            fontSize: 12,
            color: r.reste < 0 ? Colors.red : Colors.black87,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        children: [
          _ligne("Part collectée", r.collecte, Colors.green.shade700),
          if (r.globales != 0)
            _ligne("Dépenses globales", -r.globales, Colors.red),
          if (r.independantes != 0)
            _ligne("Dépenses indépendantes", -r.independantes, Colors.red),
          if (r.mixtes != 0) _ligne("Dépenses mixtes", -r.mixtes, Colors.red),
          if (r.totalEntrees != 0)
            _ligne("Entrées d'argent", r.totalEntrees, Colors.teal),
          _ligne("Reste", r.reste, Colors.indigo, gras: true),
          const Divider(),
          if (deps.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Aucune dépense dans cette rubrique.",
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            )
          else
            ...deps.map(_tuileDepense),
        ],
      ),
    );
  }

  Widget _tuileDepense(Depense d) {
    final double montant = fs.montantDepensePourFiltre(d, _section);
    final bool partiel = montant != d.montant;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.money_off, color: Colors.red, size: 20),
      title: Text(d.motif.isEmpty ? "(sans motif)" : d.motif),
      subtitle: Text(
        "${d.dateFormatee} • ${d.porteeLabel} • ${d.sectionsLabel}"
        "${d.moisImputation != null && d.moisImputation!.trim().isNotEmpty ? '\nImputée à : ${d.moisImputation}' : ''}"
        "${partiel ? '\nPart de la section sur ${_fc(d.montant)}' : ''}",
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Text(
        "- ${_fc(montant)}",
        style: const TextStyle(
            color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Onglet 2 : tableau mois par mois
  // --------------------------------------------------------------------------
  Widget _ongletTableau() {
    final mois = fs.months;
    final statsParMois = {for (final m in mois) m: _stats(m)};
    final rubriques = _toutesRubriques();

    double cellule(String m, String rub) =>
        statsParMois[m]!.rubriqueParNom(rub)?.total ?? 0;

    const styleEntete =
        TextStyle(fontWeight: FontWeight.bold, color: Colors.white);
    final totalParMois = {
      for (final m in mois) m: statsParMois[m]!.totalDepenses,
    };
    final double totalGeneral =
        totalParMois.values.fold(0.0, (a, b) => a + b);

    DataCell celluleTap(String m, String? rub, double v, {bool gras = false}) {
      return DataCell(
        Text(
          v == 0 ? "—" : formatMontant(v),
          style: TextStyle(
            color: v == 0 ? Colors.grey : Colors.red.shade700,
            fontWeight: gras ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        onTap: v == 0 ? null : () => _detailCase(m, rub),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _filtreSection(),
        const SizedBox(height: 8),
        const Text(
          "Argent déjà dépensé (FC) par rubrique et par mois. Touchez une "
          "case pour voir les dépenses.",
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        if (rubriques.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text("Aucune rubrique ni dépense pour l'instant.",
                  style: TextStyle(color: Colors.grey)),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.indigo),
              columnSpacing: 18,
              columns: [
                const DataColumn(label: Text("Rubrique", style: styleEntete)),
                ...mois.map((m) => DataColumn(
                    numeric: true, label: Text(m, style: styleEntete))),
                const DataColumn(
                    numeric: true, label: Text("Total", style: styleEntete)),
              ],
              rows: [
                ...rubriques.map((rub) {
                  final double total =
                      mois.fold(0.0, (a, m) => a + cellule(m, rub));
                  return DataRow(cells: [
                    DataCell(Text(rub,
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                    ...mois.map((m) => celluleTap(m, rub, cellule(m, rub))),
                    celluleTap(_annee, rub, total, gras: true),
                  ]);
                }),
                DataRow(
                  color: WidgetStateProperty.all(Colors.indigo.withAlpha(25)),
                  cells: [
                    const DataCell(Text("TOTAL",
                        style: TextStyle(fontWeight: FontWeight.bold))),
                    ...mois.map((m) =>
                        celluleTap(m, null, totalParMois[m]!, gras: true)),
                    celluleTap(_annee, null, totalGeneral, gras: true),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Détail d'une case du tableau : dépenses d'un mois (ou de l'année) pour
  // une rubrique (ou toutes).
  void _detailCase(String mois, String? rubrique) {
    final List<Depense> deps;
    if (mois == _annee) {
      // Total de l'année = somme des mois scolaires (même base que le
      // tableau).
      deps = [
        for (final m in fs.months)
          ..._stats(m).depenses.where((d) =>
              (rubrique == null || d.rubriqueAffichee == rubrique) &&
              fs.montantDepensePourFiltre(d, _section) != 0),
      ];
    } else {
      deps = _stats(mois)
          .depenses
          .where((d) =>
              (rubrique == null || d.rubriqueAffichee == rubrique) &&
              fs.montantDepensePourFiltre(d, _section) != 0)
          .toList();
    }
    final double total =
        deps.fold(0.0, (a, d) => a + fs.montantDepensePourFiltre(d, _section));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("${rubrique ?? 'Toutes les rubriques'} — "
            "${_libelleMois(mois)}"),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: deps
                      .map((d) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _tuileDepense(d),
                              if (rubrique == null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 40, bottom: 4),
                                  child: Text(
                                      "Rubrique : ${d.rubriqueAffichee}",
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.indigo)),
                                ),
                            ],
                          ))
                      .toList(),
                ),
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: Text("${deps.length} dépense(s)",
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Text("- ${_fc(total)}",
                      style: const TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Fermer"),
          ),
          if (mois != _annee)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _mois = mois;
                  _rubrique = rubrique;
                });
                _tabs.animateTo(0);
              },
              child: const Text("Voir le détail du mois"),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Dépenses par rubrique et par mois"),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.calendar_today), text: "Un mois"),
            Tab(icon: Icon(Icons.table_chart), text: "Mois par mois"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ongletUnMois(),
          _ongletTableau(),
        ],
      ),
    );
  }
}
