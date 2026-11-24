import 'package:flutter/material.dart';
import '../frais_scolaires.dart';
import '../models.dart';

// ============================================================================
// ⚡ NOUVEAU — Écran « Retenues sur paiements »
// Liste des règles + résumé (jour / mois / année) + éditeur de règle.
// ============================================================================

class RetenuesScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const RetenuesScreen({super.key, required this.fraisScolaires});

  @override
  State<RetenuesScreen> createState() => _RetenuesScreenState();
}

class _RetenuesScreenState extends State<RetenuesScreen> {
  FraisScolaires get fs => widget.fraisScolaires;

  Future<void> _ouvrirEditeur([RetenueRegle? existante]) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RetenueRegleEditorScreen(
          fraisScolaires: fs,
          regle: existante,
        ),
      ),
    );
    if (ok == true && mounted) setState(() {});
  }

  Future<void> _supprimer(RetenueRegle r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette règle ?'),
        content: Text(
          'La règle « ${fs.libelleCibleRetenue(r)} » sera supprimée. '
              'Les paiements déjà enregistrés ne sont pas modifiés ; la '
              'répartition par pourcentages sera simplement recalculée sans '
              'ces retenues.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await fs.supprimerRegleRetenue(r.id);
      if (mounted) setState(() {});
    }
  }

  Widget _carteExplication() {
    return Card(
      color: Colors.indigo.shade50,
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Text(
          "Les retenues sont des sommes qui sortent de chaque paiement "
              "d'élève AVANT le calcul des pourcentages des administrations "
              "(ex : construction, informatique, examens…). Les 100 % "
              "encaissés ne changent pas : seul le reste est réparti selon "
              "les pourcentages.\n\n"
              "Chaque école définit ses propres noms et montants. Une règle "
              "peut viser toute l'école, une section ou une classe (la "
              "classe prime sur la section, qui prime sur l'école).",
          style: TextStyle(fontSize: 12.5),
        ),
      ),
    );
  }

  Widget _carteResume() {
    TableRow entete() => const TableRow(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('Période',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('Encaissé',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('Retenues',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('Réparti',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );

    TableRow ligne(String titre, String periode) {
      final double brut = fs.getMoneyCollectedForPeriod(periode);
      final double ret = fs.getTotalRetenues(periode);
      Widget cell(String t, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          t,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 12.5,
            color: color,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
      return TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(titre, style: const TextStyle(fontSize: 12.5)),
          ),
          cell(formatMontant(brut)),
          cell(formatMontant(ret), color: Colors.orange.shade800),
          cell(formatMontant(brut - ret),
              color: Colors.green.shade800, bold: true),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Résumé (en FC)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1.3),
                1: FlexColumnWidth(1.4),
                2: FlexColumnWidth(1.2),
                3: FlexColumnWidth(1.4),
              },
              children: [
                entete(),
                ligne("Aujourd'hui", 'today'),
                ligne('Ce mois', 'month'),
                ligne('Cette année', 'year'),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '« Réparti » = montant sur lequel les pourcentages des '
                  'administrations sont appliqués.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _carteVide() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            "Aucune règle pour le moment.\nAppuyez sur « Nouvelle règle » "
                "pour en créer une.\n\nTant qu'il n'y a aucune règle, "
                "l'application fonctionne exactement comme avant.",
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _carteRegle(RetenueRegle r, RetenueStatRegle? stat) {
    final double? ref = fs.plusPetitFraisPourCible(r.section, r.classe);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    fs.libelleCibleRetenue(r),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Switch(
                  value: r.actif,
                  onChanged: (v) async {
                    await fs.basculerRegleRetenue(r.id, v);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
            Text(
              fs.libelleMoisRetenue(r) +
                  (r.actif ? '' : '  •  DÉSACTIVÉE'),
              style: TextStyle(
                fontSize: 12,
                color: r.actif ? Colors.black54 : Colors.red.shade700,
              ),
            ),
            const Divider(),
            ...r.items.map(
                  (it) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(it.nom)),
                    Text('${formatMontant(it.montant)} FC'),
                  ],
                ),
              ),
            ),
            const Divider(),
            Row(
              children: [
                const Expanded(
                  child: Text('Total par paiement complet',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Text(
                  '${formatMontant(r.total)} FC',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (ref != null) ...[
              const SizedBox(height: 4),
              Text(
                'Frais mensuel le plus bas concerné : ${formatMontant(ref)} FC '
                    '→ reste à répartir : ${formatMontant(ref - r.total)} FC.',
                style: const TextStyle(fontSize: 11.5, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: stat == null
                  ? const Text(
                'Déjà retenu cette année : 0 FC',
                style: TextStyle(fontSize: 12.5),
              )
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Déjà retenu cette année : '
                        '${formatMontant(stat.total)} FC '
                        '(${stat.nbPaiements} paiement(s))',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...r.items.map(
                        (it) => Text(
                      '• ${it.nom} : '
                          '${formatMontant(stat.parItem[it.id] ?? 0)} FC',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.edit),
                  label: const Text('Modifier'),
                  onPressed: () => _ouvrirEditeur(r),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('Supprimer',
                      style: TextStyle(color: Colors.red)),
                  onPressed: () => _supprimer(r),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final regles = fs.getRegles();
    final resumeAnnee = fs.calculerResumeRetenues('year');
    final Map<String, RetenueStatRegle> statParId = {
      for (final s in resumeAnnee.regles) s.regle.id: s,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Retenues sur paiements')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _ouvrirEditeur(),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle règle'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _carteExplication(),
          const SizedBox(height: 12),
          _carteResume(),
          const SizedBox(height: 12),
          if (regles.isEmpty)
            _carteVide()
          else
            ...regles.map((r) => _carteRegle(r, statParId[r.id])),
        ],
      ),
    );
  }
}

// ============================================================================
// ÉDITEUR D'UNE RÈGLE
// ============================================================================

class _ItemCtrl {
  final String id;
  final TextEditingController nom;
  final TextEditingController montant;

  _ItemCtrl({required this.id, String n = '', String m = ''})
      : nom = TextEditingController(text: n),
        montant = TextEditingController(text: m);

  void dispose() {
    nom.dispose();
    montant.dispose();
  }
}

class RetenueRegleEditorScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  final RetenueRegle? regle;

  const RetenueRegleEditorScreen({
    super.key,
    required this.fraisScolaires,
    this.regle,
  });

  @override
  State<RetenueRegleEditorScreen> createState() =>
      _RetenueRegleEditorScreenState();
}

class _RetenueRegleEditorScreenState extends State<RetenueRegleEditorScreen> {
  FraisScolaires get fs => widget.fraisScolaires;

  late String _section;
  late String _classe;
  late Set<String> _mois;
  late bool _actif;
  final List<_ItemCtrl> _items = [];
  int _compteur = 0;
  String? _erreur;
  bool _enCours = false;

  static const List<String> _suggestions = [
    'Construction',
    'Frais informatiques',
    "Frais d'examens",
    'Reste juin',
    'Cours supplémentaires',
  ];

  @override
  void initState() {
    super.initState();
    final r = widget.regle;
    _section = r?.section ?? '';
    _classe = r?.classe ?? '';
    _mois = Set<String>.from(r?.mois ?? const <String>[]);
    _actif = r?.actif ?? true;
    if (r != null) {
      for (final it in r.items) {
        _items.add(_ItemCtrl(
          id: it.id,
          n: it.nom,
          m: it.montant == it.montant.roundToDouble()
              ? it.montant.toStringAsFixed(0)
              : it.montant.toString(),
        ));
      }
    }
    if (_items.isEmpty) _ajouterItem();
  }

  @override
  void dispose() {
    for (final c in _items) {
      c.dispose();
    }
    super.dispose();
  }

  String _nouvelId() =>
      'RTI${DateTime.now().microsecondsSinceEpoch}_${_compteur++}';

  void _ajouterItem([String nom = '']) {
    setState(() => _items.add(_ItemCtrl(id: _nouvelId(), n: nom)));
  }

  double? _parse(String s) {
    final t = s.trim().replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  double get _total {
    double t = 0;
    for (final c in _items) {
      final v = _parse(c.montant.text);
      if (v != null && v > 0) t += v;
    }
    return t;
  }

  List<String> _moisFinal() {
    final tries = fs.months.where(_mois.contains).toList();
    if (tries.length >= fs.months.length) return [];
    return tries;
  }

  Future<void> _enregistrer() async {
    final items = <RetenueItem>[];
    for (final c in _items) {
      final nom = c.nom.text.trim();
      final txt = c.montant.text.trim();
      if (nom.isEmpty && txt.isEmpty) continue;
      final m = _parse(txt);
      if (nom.isEmpty) {
        setState(() => _erreur = 'Chaque retenue doit avoir un nom.');
        return;
      }
      if (m == null || m <= 0) {
        setState(() =>
        _erreur = 'Le montant de « $nom » doit être supérieur à zéro.');
        return;
      }
      items.add(RetenueItem(id: c.id, nom: nom, montant: m));
    }

    final regle = RetenueRegle(
      id: widget.regle?.id ?? 'RET${DateTime.now().microsecondsSinceEpoch}',
      section: _section,
      classe: _section.isEmpty ? '' : _classe,
      mois: _moisFinal(),
      items: items,
      actif: _actif,
    );

    setState(() {
      _erreur = null;
      _enCours = true;
    });
    final String? err = await fs.enregistrerRegleRetenue(regle);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _erreur = err;
        _enCours = false;
      });
      return;
    }
    Navigator.pop(context, true);
  }

  Widget _dropdownSection() {
    final sections = fs.config.sections;
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
          value: '', child: Text("Toute l'école")),
      ...sections.map(
              (s) => DropdownMenuItem<String>(value: s, child: Text(s))),
      if (_section.isNotEmpty && !sections.contains(_section))
        DropdownMenuItem<String>(value: _section, child: Text(_section)),
    ];
    return DropdownButtonFormField<String>(
      value: _section,
      decoration: const InputDecoration(
        labelText: 'Section',
        border: OutlineInputBorder(),
      ),
      items: items,
      onChanged: (v) => setState(() {
        _section = v ?? '';
        _classe = '';
      }),
    );
  }

  Widget _dropdownClasse() {
    final classes = fs.getClassesForSection(_section);
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
          value: '', child: Text('Toutes les classes de la section')),
      ...classes.map(
              (c) => DropdownMenuItem<String>(value: c, child: Text(c))),
      if (_classe.isNotEmpty && !classes.contains(_classe))
        DropdownMenuItem<String>(value: _classe, child: Text(_classe)),
    ];
    return DropdownButtonFormField<String>(
      value: _classe,
      decoration: const InputDecoration(
        labelText: 'Classe',
        border: OutlineInputBorder(),
      ),
      items: items,
      onChanged: (v) => setState(() => _classe = v ?? ''),
    );
  }

  Widget _selecteurMois() {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        FilterChip(
          label: const Text('Tous les mois'),
          selected: _mois.isEmpty,
          onSelected: (_) => setState(() => _mois.clear()),
        ),
        ...fs.months.map(
              (m) => FilterChip(
            label: Text(m),
            selected: _mois.contains(m),
            onSelected: (sel) => setState(() {
              if (sel) {
                _mois.add(m);
              } else {
                _mois.remove(m);
              }
            }),
          ),
        ),
      ],
    );
  }

  Widget _ligneItem(_ItemCtrl c) {
    return Padding(
      key: ValueKey(c.id),
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: c.nom,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nom de la retenue',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: c.montant,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Montant (FC)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Retirer',
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () {
              setState(() {
                _items.remove(c);
                c.dispose();
                if (_items.isEmpty) _ajouterItem();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _apercu() {
    final double total = _total;
    final double? ref = fs.plusPetitFraisPourCible(_section, _classe);
    final admins = fs.config.administrations;
    final double? reste = ref == null ? null : ref - total;

    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total des retenues : ${formatMontant(total)} FC',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold),
            ),
            if (ref != null) ...[
              const SizedBox(height: 4),
              Text(
                'Frais mensuel le plus bas concerné : '
                    '${formatMontant(ref)} FC',
                style: const TextStyle(fontSize: 12.5),
              ),
              Text(
                'Reste réparti aux administrations : '
                    '${formatMontant(reste!)} FC',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: reste < 0 ? Colors.red : Colors.green.shade800,
                ),
              ),
              if (reste >= 0 && admins.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text("Exemple pour un paiement complet :",
                    style: TextStyle(
                        fontSize: 12, fontStyle: FontStyle.italic)),
                ...admins.map(
                      (a) => Text(
                    '• ${a.nom} (${a.pourcentage.toStringAsFixed(0)}%) : '
                        '${formatMontant(reste * a.pourcentage / 100)} FC',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.regle == null
            ? 'Nouvelle règle de retenue'
            : 'Modifier la règle'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            icon: _enCours
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.save),
            label: const Text('Enregistrer la règle'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _enCours ? null : _enregistrer,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('1. À qui s\'applique cette règle ?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _dropdownSection(),
          if (_section.isNotEmpty) ...[
            const SizedBox(height: 10),
            _dropdownClasse(),
          ],
          const SizedBox(height: 20),
          const Text('2. Pour quels mois ?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _selecteurMois(),
          const SizedBox(height: 20),
          const Text('3. Les retenues (nom + montant)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Écrivez les noms et montants que vous voulez. Vous pouvez en '
                'ajouter autant que nécessaire.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          ..._items.map(_ligneItem),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Ajouter une retenue'),
                onPressed: () => _ajouterItem(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 8, right: 4),
                child: Text('Suggestions :',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
              ),
              ..._suggestions.map(
                    (s) => ActionChip(
                  label: Text(s, style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    // Remplit la première ligne vide, sinon en ajoute une.
                    final vide = _items.where(
                            (c) => c.nom.text.trim().isEmpty);
                    if (vide.isNotEmpty) {
                      setState(() => vide.first.nom.text = s);
                    } else {
                      _ajouterItem(s);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _apercu(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Règle active'),
            value: _actif,
            onChanged: (v) => setState(() => _actif = v),
          ),
          if (_erreur != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Text(_erreur!,
                  style: TextStyle(color: Colors.red.shade800)),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}