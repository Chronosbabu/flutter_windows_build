part of frais_scolaires;

// ============================================================================
// ⚡ NOUVEAU — RÉSULTAT DU CALCUL « DIFFÉRENCE ACCUMULÉE »
// ============================================================================
// Différence = montant réel payé − montant affiché sur le rapport, cumulée sur
// tous les paiements de l'année (élèves actifs + archivés).
//   - parSection : { 'Primaire': 125000 }
//   - parClasse  : { 'Primaire': { '1ère A': 40000, '2ème': 85000 } }
// ============================================================================
class DifferenceRapport {
  final Map<String, double> parSection;
  final Map<String, Map<String, double>> parClasse;

  const DifferenceRapport({
    this.parSection = const {},
    this.parClasse = const {},
  });

  double get total => parSection.values.fold(0.0, (a, b) => a + b);
}

extension FraisScolairesRapports on FraisScolaires {
  static const List<String> _joursSemaine = [
    'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'
  ];

  static const List<String> _moisCalendrier = [
    'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
    'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'
  ];

  String get _dateGenerationFormatee {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final jour = _joursSemaine[now.weekday - 1];
    return '$jour ${two(now.day)}/${two(now.month)}/${now.year} à '
        '${two(now.hour)}:${two(now.minute)}';
  }

  // ==========================================================================
  // ⚡ NOUVEAU — MONTANTS PERSONNALISÉS DU RAPPORT (fonction optionnelle)
  // --------------------------------------------------------------------------
  // Quand la fonction est activée (page de génération de rapport, 3 appuis sur
  // le titre + mot de passe), les montants PAYÉS affichés dans les PDF de
  // rapport sont recalculés proportionnellement :
  //
  //     montant affiché = montant réel × montant du rapport / montant réel
  //                                      de la classe (frais mensuel)
  //
  // Exemple : frais réel 65 000 FC, montant du rapport 60 000 FC
  //   - élève ayant payé 65 000 -> le rapport affiche 60 000 ;
  //   - élève ayant payé 32 500 -> le rapport affiche 30 000.
  //
  // RIEN d'autre n'est modifié : les données, les reçus, l'historique et
  // l'application restent sur les montants réels. Si la fonction est
  // désactivée (ou qu'aucun montant n'est défini), toutes les fonctions
  // ci-dessous renvoient exactement les valeurs d'origine.
  // ==========================================================================

  bool get _rapportPersonnaliseEnVigueur => rapportPersonnalise.enVigueur;

  /// Montant mensuel réel de référence d'une classe (ou d'une section si
  /// [classeNumero] est absent). Publique : utilisée par la boîte de dialogue.
  double montantReferencePourRapport(String section, [String? classeNumero]) {
    if (classeNumero != null && classeNumero.trim().isNotEmpty) {
      final double? v =
      config.feesByClasse['$section|${classeNumero.trim()}'];
      if (v != null) return v;
    }
    return config.feesBySection[section] ??
        FraisScolaires._montantSecoursSiNonConfigure;
  }

  /// Convertit un montant réel en montant à afficher sur le rapport.
  double _versMontantRapport(String section, String classe, double reel) {
    if (!_rapportPersonnaliseEnVigueur) return reel;
    if (reel == 0) return reel;
    final String numero = classeNumeroFromFullClasse(classe);
    final double? cible = rapportPersonnalise.montantPour(section, numero);
    if (cible == null || cible <= 0) return reel;
    final double ref = montantReferencePourRapport(section, numero);
    if (ref <= 0 || cible >= ref) return reel;
    return reel * cible / ref;
  }

  double _versMontantRapportEleve(Eleve eleve, double reel) =>
      _versMontantRapport(eleve.section, eleve.classe, reel);

  /// ⚡ NOUVEAU — Différence accumulée (montant retenu) par section et par
  /// classe : somme, sur tous les paiements de l'année (élèves actifs +
  /// archivés), de (montant réel payé − montant affiché sur le rapport).
  /// Retourne un résultat vide si la fonction n'est pas en vigueur.
  /// Publique : utilisée par la boîte de dialogue cachée.
  DifferenceRapport differenceAccumuleeRapport() {
    if (!_rapportPersonnaliseEnVigueur) return const DifferenceRapport();
    final Map<String, double> parSection = {};
    final Map<String, Map<String, double>> parClasse = {};
    for (final e in [...currentData.eleves, ...elevesSupprimesData.eleves]) {
      final double paye =
      months.fold<double>(0.0, (s, m) => s + (e.paid[m] ?? 0.0));
      if (paye == 0) continue;
      final double diff = paye - _versMontantRapportEleve(e, paye);
      if (diff.abs() < 0.0001) continue;
      parSection[e.section] = (parSection[e.section] ?? 0.0) + diff;
      final classes = parClasse.putIfAbsent(e.section, () => {});
      classes[e.classe] = (classes[e.classe] ?? 0.0) + diff;
    }
    return DifferenceRapport(parSection: parSection, parClasse: parClasse);
  }

  /// Total de l'année affiché dans le rapport (élèves actifs + archivés).
  double _totalAnneeRapport() {
    if (!_rapportPersonnaliseEnVigueur) return getYearTotalCollected();
    double total = 0.0;
    for (final e in [...currentData.eleves, ...elevesSupprimesData.eleves]) {
      final double paye =
      months.fold<double>(0.0, (s, m) => s + (e.paid[m] ?? 0.0));
      total += _versMontantRapportEleve(e, paye);
    }
    return total;
  }

  /// Total du mois en cours affiché dans le rapport.
  double _totalMoisCourantRapport() {
    if (!_rapportPersonnaliseEnVigueur) return getCurrentMonthTotalCollected();
    final idx = _schoolMonthIndexForToday();
    if (idx < 0 || idx >= months.length) return 0.0;
    final moisCourant = months[idx];
    double total = 0.0;
    for (final e in [...currentData.eleves, ...elevesSupprimesData.eleves]) {
      total += _versMontantRapportEleve(e, e.paid[moisCourant] ?? 0.0);
    }
    return total;
  }

  /// Récapitulatif mensuel (rapport annuel).
  List<double> _evolutionMensuelleRapport() {
    if (!_rapportPersonnaliseEnVigueur) return getMonthlyEvolution();
    return months
        .map((m) => currentData.eleves.fold<double>(
        0.0,
            (sum, e) =>
        sum + _versMontantRapportEleve(e, e.paid[m] ?? 0.0)))
        .toList();
  }

  /// Collecte par section (jour / mois en cours / année) telle qu'affichée
  /// dans la partie « Dépenses » du rapport.
  Map<String, double> _collecteParSectionRapport(String period) {
    final Map<String, double> result = {};
    for (final e in [...currentData.eleves, ...elevesSupprimesData.eleves]) {
      final double montant =
      _versMontantRapportEleve(e, _getStudentAmountForPeriod(e, period));
      if (period != 'year' && montant == 0) continue;
      result[e.section] = (result[e.section] ?? 0) + montant;
    }
    return result;
  }

  // ==========================================================================
  // ⚡ NOUVEAU — OUTILS POUR LES RAPPORTS D'UN MOIS PASSÉ
  // ==========================================================================

  /// Retourne l'année et le mois calendaires (1er du mois) correspondant à un
  /// mois scolaire (ex : "Septembre" de l'année 2025-2026 -> 01/09/2025).
  DateTime _dateRepereMois(String mois) {
    int idx = months.indexOf(mois);
    if (idx < 0) idx = 0;
    final int moisCalendrier = idx < 4 ? 9 + idx : idx - 3;

    int anneeDebut = DateTime.now().year;
    int anneeFin = anneeDebut;
    final parts = currentYear.split('-');
    if (parts.length == 2) {
      anneeDebut = int.tryParse(parts[0].trim()) ?? anneeDebut;
      anneeFin = int.tryParse(parts[1].trim()) ?? (anneeDebut + 1);
    }
    final int annee = idx < 4 ? anneeDebut : anneeFin;
    return DateTime(annee, moisCalendrier, 1);
  }

  String _libelleMoisCalendrier(String mois) {
    final d = _dateRepereMois(mois);
    return '${_moisCalendrier[d.month - 1]} ${d.year}';
  }

  /// Élèves (année en cours) ayant payé quelque chose pour le mois donné.
  List<Eleve> _elevesAyantPayeMois(String mois) {
    return currentData.eleves
        .where((e) => (e.paid[mois] ?? 0) > 0)
        .toList();
  }

  /// Total collecté pour un mois scolaire donné (élèves actifs + archivés).
  /// ⚡ Si les montants personnalisés sont actifs, le total est celui du
  /// rapport ; sinon le calcul d'origine est conservé tel quel.
  double _totalCollecteMois(String mois) {
    if (_rapportPersonnaliseEnVigueur) {
      double total = 0.0;
      for (final e in [...currentData.eleves, ...elevesSupprimesData.eleves]) {
        total += _versMontantRapportEleve(e, e.paid[mois] ?? 0.0);
      }
      return total;
    }
    return currentData.eleves
        .fold(0.0, (sum, e) => sum + (e.paid[mois] ?? 0)) +
        elevesSupprimesData.eleves
            .fold(0.0, (sum, e) => sum + (e.paid[mois] ?? 0));
  }

  /// Collecte par section pour un mois scolaire donné.
  Map<String, double> _collecteMoisParSection(String mois) {
    final Map<String, double> result = {};
    for (final e in [...currentData.eleves, ...elevesSupprimesData.eleves]) {
      final montant = _versMontantRapportEleve(e, e.paid[mois] ?? 0.0);
      if (montant != 0) {
        result[e.section] = (result[e.section] ?? 0) + montant;
      }
    }
    return result;
  }

  /// Montant payé par un élève sur la période. Si [mois] est fourni et que la
  /// période est 'month', on prend le mois choisi au lieu du mois en cours.
  /// ⚡ Le montant est converti en montant de rapport si la fonction est
  /// active (sinon valeur réelle inchangée).
  double _montantEleve(Eleve eleve, String period, String? mois) {
    final double reel = (period == 'month' && mois != null)
        ? (eleve.paid[mois] ?? 0.0)
        : _getStudentAmountForPeriod(eleve, period);
    return _versMontantRapportEleve(eleve, reel);
  }

  bool _paiementAutreFraisDansPeriodeMois(
      AutreFraisPaiement p, String period, String? mois) {
    if (period == 'month' && mois != null) {
      final d = _dateRepereMois(mois);
      return p.date.year == d.year && p.date.month == d.month;
    }
    return paiementAutreFraisDansPeriode(p, period);
  }

  /// Construit les statistiques de dépenses à partir d'une collecte par
  /// section et d'une liste de dépenses déjà filtrées.
  DepensePeriodeStats _construireStatsDepenses({
    required String period,
    required Map<String, double> collecteAll,
    required List<Depense> depenses,
    String? sectionFilter,
  }) {
    final collecteBySection = <String, double>{};
    collecteAll.forEach((s, v) {
      if (sectionFilter == null || s == sectionFilter) {
        collecteBySection[s] = v;
      }
    });
    final double totalCollecte =
    collecteBySection.values.fold(0.0, (a, b) => a + b);

    final Map<String, RubriqueStat> rub = {};
    for (final admin in config.administrations) {
      final nom = admin.nom.trim();
      if (nom.isEmpty) continue;
      rub[nom] = RubriqueStat(
        rubrique: nom,
        pourcentage: admin.pourcentage,
        collecte: totalCollecte * (admin.pourcentage / 100),
      );
    }

    final Map<String, SectionStat> secStats = {};
    final sectionsBase = sectionFilter != null
        ? <String>[sectionFilter]
        : List<String>.from(config.sections);
    for (final s in sectionsBase) {
      secStats[s] =
          SectionStat(section: s, collecte: collecteBySection[s] ?? 0);
    }
    collecteBySection.forEach((s, v) {
      secStats.putIfAbsent(s, () => SectionStat(section: s, collecte: v));
    });

    double globales = 0;
    double independantes = 0;
    double mixtes = 0;

    for (final d in depenses) {
      final cle = d.rubriqueAffichee;
      final r = rub.putIfAbsent(
        cle,
            () => RubriqueStat(rubrique: cle, pourcentage: 0, collecte: 0),
      );
      if (d.portee == kDepenseGlobale) {
        if (sectionFilter == null) {
          r.globales += d.montant;
          globales += d.montant;
        }
      } else {
        final parts = repartitionDepenseParSection(d);
        parts.forEach((s, amt) {
          if (sectionFilter != null && s != sectionFilter) return;
          final st = secStats.putIfAbsent(
              s, () => SectionStat(section: s, collecte: 0));
          if (d.portee == kDepenseIndependante) {
            r.independantes += amt;
            st.independantes += amt;
            independantes += amt;
          } else {
            r.mixtes += amt;
            st.mixtes += amt;
            mixtes += amt;
          }
        });
      }
    }

    return DepensePeriodeStats(
      period: period,
      depenses: depenses,
      rubriques: rub.values.toList(),
      sections: secStats.values.toList(),
      totalCollecte: totalCollecte,
      globales: globales,
      independantes: independantes,
      mixtes: mixtes,
      globalesExclues: sectionFilter != null,
    );
  }

  /// Équivalent de computeDepensesStats('month') mais pour un mois choisi.
  DepensePeriodeStats _computeDepensesStatsMois(
      String mois, {
        String? sectionFilter,
        String? classFilter,
      }) {
    final repere = _dateRepereMois(mois);
    final depenses = (depensesByYear[currentYear] ?? []).where((d) {
      final bool okPeriode =
          d.date.year == repere.year && d.date.month == repere.month;
      return okPeriode && _depenseConcerneFiltre(d, sectionFilter, classFilter);
    }).toList();
    depenses.sort((a, b) => a.date.compareTo(b.date));

    return _construireStatsDepenses(
      period: 'month',
      collecteAll: _collecteMoisParSection(mois),
      depenses: depenses,
      sectionFilter: sectionFilter,
    );
  }

  /// ⚡ NOUVEAU — équivalent de computeDepensesStats(period) mais avec la
  /// collecte exprimée en montants de rapport (utilisé uniquement quand la
  /// fonction « montants personnalisés » est active).
  DepensePeriodeStats _computeDepensesStatsRapport(
      String period, {
        String? sectionFilter,
        String? classFilter,
      }) {
    return _construireStatsDepenses(
      period: period,
      collecteAll: _collecteParSectionRapport(period),
      depenses: getDepensesForPeriod(
        period,
        sectionFilter: sectionFilter,
        classFilter: classFilter,
      ),
      sectionFilter: sectionFilter,
    );
  }

  // ==========================================================================

  List<pw.Widget> _buildSignatureSection([String? city]) {
    if (signataires.isEmpty) return [];

    final villeAffichee =
    (city != null && city.trim().isNotEmpty) ? city.trim() : 'Lubumbashi';

    final rows = <List<Signataire>>[];
    for (var i = 0; i < signataires.length; i += 3) {
      final end = (i + 3 > signataires.length) ? signataires.length : i + 3;
      rows.add(signataires.sublist(i, end));
    }

    pw.Widget buildColonne(Signataire s) {
      return pw.Expanded(
        child: pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.SizedBox(height: 34),
              pw.Container(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(width: 0.8, color: PdfColors.black),
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                s.nom.isNotEmpty ? s.nom : ' ',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                s.fonction.isNotEmpty ? s.fonction : ' ',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return [
      pw.SizedBox(height: 36),
      pw.Divider(thickness: 0.6, color: PdfColors.grey400),
      pw.SizedBox(height: 4),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Fait à $villeAffichee, le : $_dateGenerationFormatee',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ),
      pw.SizedBox(height: 26),
      ...rows.map((rowSignataires) {
        final widgets = rowSignataires.map(buildColonne).toList();
        while (widgets.length < 3) {
          widgets.add(pw.Expanded(child: pw.SizedBox()));
        }
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 24),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: widgets,
          ),
        );
      }),
    ];
  }

  Map<int, pw.TableColumnWidth> _buildColumnWidths(List<double> flexRatios) {
    return {
      for (var i = 0; i < flexRatios.length; i++)
        i: pw.FlexColumnWidth(flexRatios[i]),
    };
  }

  double _tableCellFontSize(int columnCount) {
    if (columnCount <= 6) return 9;
    if (columnCount <= 8) return 8.5;
    if (columnCount <= 10) return 8;
    if (columnCount <= 13) return 7.5;
    return 6.5;
  }

  double _tableHeaderFontSize(int columnCount) {
    if (columnCount <= 6) return 9;
    if (columnCount <= 8) return 8.5;
    if (columnCount <= 10) return 8;
    if (columnCount <= 13) return 7.5;
    return 7;
  }

  String _tauxMensuelLabel(List<Eleve> eleves, [String? moisCible]) {
    if (eleves.isEmpty) return '-';
    final mois = moisCible ?? currentSchoolMonthName ?? months.first;
    double? min;
    double? max;
    for (final e in eleves) {
      // ⚡ Taux exprimé en montant de rapport si la fonction est active.
      final v = _versMontantRapport(
          e.section, e.classe, getRequiredForMonth(mois, e.section, e.classe));
      if (min == null || v < min) min = v;
      if (max == null || v > max) max = v;
    }
    if (min == null || max == null) return '-';
    if ((max - min).abs() < 0.5) return formatMontant(min);
    return '${formatMontant(min)} - ${formatMontant(max)}';
  }

  String _pctLabel(double p) =>
      p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(1);

  Map<String, dynamic> _computeStudentCounts(List<Eleve> students) {
    final Map<String, int> parSection = {};
    final Map<String, int> parClasse = {};

    for (final e in students) {
      parSection[e.section] = (parSection[e.section] ?? 0) + 1;
      final classeKey = "${e.section} - ${e.classe}";
      parClasse[classeKey] = (parClasse[classeKey] ?? 0) + 1;
    }

    final sectionsTriees = parSection.keys.toList()..sort();
    final classesTriees = parClasse.keys.toList()..sort();

    return {
      'total': students.length,
      'parSection': {
        for (final s in sectionsTriees) s: parSection[s]!,
      },
      'parClasse': {
        for (final c in classesTriees) c: parClasse[c]!,
      },
    };
  }

  List<pw.Widget> _buildStudentCountSection(
      List<Eleve> students, {
        String label = "Élèves concernés par ce rapport",
      }) {
    final counts = _computeStudentCounts(students);
    final int total = counts['total'] as int;
    final Map<String, int> parSection =
    Map<String, int>.from(counts['parSection'] as Map);
    final Map<String, int> parClasse =
    Map<String, int>.from(counts['parClasse'] as Map);

    return [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.indigo50,
          border: pw.Border.all(color: PdfColors.indigo200, width: 0.8),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              "NOMBRE D'ÉLÈVES — $label",
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo900,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              "Total général : $total élève(s)",
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (parSection.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text(
                "Par section :",
                style: pw.TextStyle(
                    fontSize: 10.5, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 3),
              ...parSection.entries.map(
                    (entry) => pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 8, bottom: 1),
                  child: pw.Text(
                    "• ${entry.key} : ${entry.value} élève(s)",
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
              ),
            ],
            if (parClasse.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text(
                "Par classe :",
                style: pw.TextStyle(
                    fontSize: 10.5, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 3),
              ...parClasse.entries.map(
                    (entry) => pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 8, bottom: 1),
                  child: pw.Text(
                    "• ${entry.key} : ${entry.value} élève(s)",
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  List<pw.Widget> _buildRepartitionParOption(
      List<Eleve> students, Map<String, double> totalBySection,
      [String? moisCible]) {
    if (!aDesOptionsActives) return [];
    if (config.administrations.isEmpty || totalBySection.isEmpty) return [];

    final groupes = _groupesOptions(totalBySection.keys);
    if (!groupes.any((g) => g.estOption)) return [];

    final admins = config.administrations;

    final List<double> totaux = [];
    final List<int> effectifs = [];
    final List<String> taux = [];
    final List<Eleve> tousLesEleves = [];

    for (final g in groupes) {
      final double total = g.sections
          .fold<double>(0.0, (sum, s) => sum + (totalBySection[s] ?? 0));
      final List<Eleve> elevesGroupe = students
          .where((e) =>
      g.sections.contains(e.section) &&
          (totalBySection[e.section] ?? 0) > 0)
          .toList();
      totaux.add(total);
      effectifs.add(elevesGroupe.length);
      taux.add(_tauxMensuelLabel(elevesGroupe, moisCible));
      tousLesEleves.addAll(elevesGroupe);
    }

    final double totalGeneral = totaux.fold(0.0, (sum, v) => sum + v);
    final int effectifGeneral = effectifs.fold(0, (sum, v) => sum + v);
    final String tauxGeneral = _tauxMensuelLabel(tousLesEleves, moisCible);

    final headers = <String>[
      'Rubrique',
      ...groupes.map((g) => g.estOption
          ? '${g.nom}\n(${g.sections.length} section${g.sections.length > 1 ? 's' : ''})'
          : g.nom),
      'TOTAL',
    ];

    final rows = <List<String>>[
      ['Effectif', ...effectifs.map((e) => '$e'), '$effectifGeneral'],
      ['Taux mensuel (FC)', ...taux, tauxGeneral],
      [
        'Montant collecté (FC)',
        ...totaux.map((t) => formatMontant(t)),
        formatMontant(totalGeneral),
      ],
      for (final a in admins)
        [
          '${a.nom} (${_pctLabel(a.pourcentage)}%)',
          ...totaux.map((t) => formatMontant(t * a.pourcentage / 100)),
          formatMontant(totalGeneral * a.pourcentage / 100),
        ],
    ];

    final double cellFontSize = _tableCellFontSize(headers.length);
    final double headerFontSize = _tableHeaderFontSize(headers.length);

    final optionsAffichees = groupes.where((g) => g.estOption).toList();

    return [
      pw.Text(
        "RÉPARTITION PAR OPTION ET PAR ADMINISTRATION",
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        "Regroupement des sections en options : chaque colonne réunit "
            "toutes les sections de l'option. Les sections qui ne sont dans "
            "aucune option figurent chacune dans leur propre colonne.",
        style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 10),
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        columnWidths: _buildColumnWidths([
          2.0,
          ...List<double>.filled(groupes.length, 1.4),
          1.5,
        ]),
        headerStyle: pw.TextStyle(
          fontSize: headerFontSize,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo800),
        headerAlignment: pw.Alignment.center,
        cellStyle: pw.TextStyle(fontSize: cellFontSize),
        cellAlignment: pw.Alignment.center,
        cellAlignments: {
          0: pw.Alignment.centerLeft,
        },
        cellPadding:
        const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.indigo50),
      ),
      pw.SizedBox(height: 6),
      ...optionsAffichees.map(
            (g) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 1),
          child: pw.Text(
            "• ${g.nom} = ${g.sections.join(', ')}",
            style: pw.TextStyle(
              fontSize: 9,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.grey800,
            ),
          ),
        ),
      ),
      pw.SizedBox(height: 16),
    ];
  }

  List<pw.Widget> _buildRepartitionParSectionEtAdministration(
      List<Eleve> students, String period, [String? moisCible]) {
    if (config.administrations.isEmpty || students.isEmpty) return [];

    final Map<String, double> totalBySection = {};
    for (final e in students) {
      totalBySection[e.section] =
          (totalBySection[e.section] ?? 0) +
              _montantEleve(e, period, moisCible);
    }
    totalBySection.removeWhere((_, v) => v <= 0);
    if (totalBySection.isEmpty) return [];

    final List<String> sectionsOrdonnees = [
      ...config.sections.where((s) => totalBySection.containsKey(s)),
      ...(totalBySection.keys
          .where((s) => !config.sections.contains(s))
          .toList()
        ..sort()),
    ];

    final headers = [
      'Section',
      'Effectif',
      'Montant Total (FC)',
      ...config.administrations
          .map((a) => '${a.nom}\n(${a.pourcentage.toStringAsFixed(0)}%)'),
    ];

    final Map<String, int> effectifParSection = {};
    for (final e in students) {
      if ((totalBySection[e.section] ?? 0) <= 0) continue;
      effectifParSection[e.section] =
          (effectifParSection[e.section] ?? 0) + 1;
    }

    final rows = <List<String>>[];
    for (final section in sectionsOrdonnees) {
      final double total = totalBySection[section] ?? 0;
      final dist = calculateAdminDistribution(total);
      rows.add([
        section,
        '${effectifParSection[section] ?? 0}',
        total.toStringAsFixed(0),
        ...config.administrations
            .map((a) => (dist[a.nom] ?? 0).toStringAsFixed(0)),
      ]);
    }

    final double totalGeneral =
    totalBySection.values.fold(0.0, (sum, v) => sum + v);
    final int effectifGeneral =
    effectifParSection.values.fold(0, (sum, v) => sum + v);
    final distGenerale = calculateAdminDistribution(totalGeneral);

    final columnWidths = _buildColumnWidths([
      1.7,
      0.9,
      1.5,
      ...List<double>.filled(config.administrations.length, 1.3),
    ]);
    final double cellFontSize = _tableCellFontSize(headers.length);
    final double headerFontSize = _tableHeaderFontSize(headers.length);

    return [
      pw.Text(
        "RÉPARTITION PAR SECTION ET PAR ADMINISTRATION",
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        "Détail du montant collecté et de sa répartition entre "
            "administrations, section par section. Le total général "
            "toutes sections et classes confondues figure dans le "
            "tableau récapitulatif juste en dessous.",
        style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 10),
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        columnWidths: columnWidths,
        headerStyle: pw.TextStyle(
          fontSize: headerFontSize,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
        headerAlignment: pw.Alignment.center,
        cellStyle: pw.TextStyle(fontSize: cellFontSize),
        cellAlignment: pw.Alignment.centerRight,
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.center,
        },
        cellPadding:
        const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.indigo50),
      ),
      pw.SizedBox(height: 16),

      ..._buildRepartitionParOption(students, totalBySection, moisCible),

      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.indigo50,
          border: pw.Border.all(color: PdfColors.indigo400, width: 1),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              "TOTAL GÉNÉRAL — TOUTES SECTIONS ET CLASSES CONFONDUES "
                  "($effectifGeneral élève(s))",
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo900,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: [
                'Montant Total (FC)',
                ...config.administrations.map((a) =>
                '${a.nom}\n(${a.pourcentage.toStringAsFixed(0)}%)'),
              ],
              data: [
                [
                  totalGeneral.toStringAsFixed(0),
                  ...config.administrations.map(
                          (a) => (distGenerale[a.nom] ?? 0).toStringAsFixed(0)),
                ],
              ],
              columnWidths: _buildColumnWidths([
                1.5,
                ...List<double>.filled(config.administrations.length, 1.3),
              ]),
              headerStyle: pw.TextStyle(
                fontSize: headerFontSize,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration:
              const pw.BoxDecoration(color: PdfColors.indigo900),
              headerAlignment: pw.Alignment.center,
              cellStyle: pw.TextStyle(
                fontSize: cellFontSize + 0.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo900,
              ),
              cellAlignment: pw.Alignment.center,
              cellPadding:
              const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 24),
    ];
  }

  String _periodeTitrePdf(String period) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    switch (period) {
      case 'today':
        return "DÉPENSES JOURNALIÈRES — ${two(now.day)}/${two(now.month)}/${now.year}";
      case 'month':
        return "DÉPENSES MENSUELLES — ${_moisCalendrier[now.month - 1]} ${now.year}";
      case 'year':
      default:
        return "DÉPENSES ANNUELLES — Année scolaire $currentYear";
    }
  }

  String _periodeCourtePdf(String period) {
    switch (period) {
      case 'today':
        return "du jour";
      case 'month':
        return "du mois";
      case 'year':
      default:
        return "de l'année";
    }
  }

  pw.Widget _pdfLigneMontant(String label, double value, PdfColor color,
      {bool gras = false, double fontSize = 10.5}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: fontSize,
              color: color,
              fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            '${formatMontant(value)} FC',
            style: pw.TextStyle(
              fontSize: fontSize,
              color: color,
              fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  pw.TextStyle _pdfHeaderDepenseStyle() => pw.TextStyle(
    fontSize: 8.5,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.white,
  );

  List<pw.Widget> _buildDepensesParOptionTable(DepensePeriodeStats s) {
    if (!aDesOptionsActives) return [];
    final actives = s.sections.where((x) => x.aDeLActivite).toList();
    if (actives.isEmpty) return [];

    final groupes = _groupesOptions(actives.map((x) => x.section));
    if (!groupes.any((g) => g.estOption)) return [];

    final parNom = <String, SectionStat>{
      for (final x in actives) x.section: x,
    };

    final rows = <List<String>>[];
    double totColl = 0;
    double totInd = 0;
    double totMix = 0;

    for (final g in groupes) {
      double coll = 0;
      double ind = 0;
      double mix = 0;
      for (final sec in g.sections) {
        final st = parNom[sec];
        if (st == null) continue;
        coll += st.collecte;
        ind += st.independantes;
        mix += st.mixtes;
      }
      totColl += coll;
      totInd += ind;
      totMix += mix;
      rows.add([
        g.estOption ? '${g.nom} (option)' : g.nom,
        g.estOption ? g.sections.join(', ') : '-',
        formatMontant(coll),
        formatMontant(ind),
        formatMontant(mix),
        formatMontant(ind + mix),
        formatMontant(coll - (ind + mix)),
      ]);
    }

    rows.add([
      'TOTAL',
      '',
      formatMontant(totColl),
      formatMontant(totInd),
      formatMontant(totMix),
      formatMontant(totInd + totMix),
      formatMontant(totColl - (totInd + totMix)),
    ]);

    return [
      pw.SizedBox(height: 10),
      pw.Text(
        "2 bis. Par option (regroupement de sections) — "
            "${_periodeCourtePdf(s.period).toUpperCase()}",
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.TableHelper.fromTextArray(
        headers: const [
          'Option / Section',
          'Sections incluses',
          'Collecté (FC)',
          'Dép. indépendantes',
          'Dép. mixtes (part)',
          'Total dépensé',
          'Reste (FC)',
        ],
        data: rows,
        columnWidths: _buildColumnWidths([1.8, 2.4, 1.3, 1.4, 1.4, 1.3, 1.3]),
        headerStyle: _pdfHeaderDepenseStyle(),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.red700),
        headerAlignment: pw.Alignment.center,
        cellStyle: const pw.TextStyle(fontSize: 8.5),
        cellAlignment: pw.Alignment.centerRight,
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.centerLeft,
        },
        cellPadding:
        const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.red50),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        "Les dépenses globales de l'école ne sont rattachées à aucune option.",
        style: pw.TextStyle(
            fontSize: 8.5,
            fontStyle: pw.FontStyle.italic,
            color: PdfColors.grey700),
      ),
    ];
  }

  List<pw.Widget> _buildDepensesPeriodeSection(
      DepensePeriodeStats s, {
        String? sectionFilter,
        String? titreForce,
      }) {
    final widgets = <pw.Widget>[];
    final String periodeCourte = _periodeCourtePdf(s.period);

    widgets.add(
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: const pw.BoxDecoration(
          color: PdfColors.red700,
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Text(
          (titreForce ?? _periodeTitrePdf(s.period)) +
              (sectionFilter != null ? "  |  Section : $sectionFilter" : ""),
          style: pw.TextStyle(
            fontSize: 12.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
        ),
      ),
    );
    widgets.add(pw.SizedBox(height: 8));

    widgets.add(
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.red50,
          border: pw.Border.all(color: PdfColors.red200, width: 0.8),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
        ),
        child: pw.Column(
          children: [
            _pdfLigneMontant("Total collecté $periodeCourte",
                s.totalCollecte, PdfColors.green800, gras: true),
            pw.Divider(thickness: 0.4, color: PdfColors.red200),
            if (!s.globalesExclues)
              _pdfLigneMontant("Dépenses globales (toute l'école)",
                  s.globales, PdfColors.grey900),
            _pdfLigneMontant("Dépenses indépendantes (une section)",
                s.independantes, PdfColors.grey900),
            _pdfLigneMontant("Dépenses mixtes (plusieurs sections)",
                s.mixtes, PdfColors.grey900),
            pw.Divider(thickness: 0.4, color: PdfColors.red200),
            _pdfLigneMontant("TOTAL DES DÉPENSES $periodeCourte".toUpperCase(),
                s.totalDepenses, PdfColors.red800, gras: true),
            _pdfLigneMontant(
              "RESTE APRÈS DÉPENSES",
              s.reste,
              s.reste >= 0 ? PdfColors.indigo900 : PdfColors.red800,
              gras: true,
              fontSize: 12,
            ),
          ],
        ),
      ),
    );
    widgets.add(pw.SizedBox(height: 12));

    widgets.add(pw.Text(
      "1. Par rubrique (administration) — ${periodeCourte.toUpperCase()}",
      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
    ));
    widgets.add(pw.SizedBox(height: 4));
    if (s.rubriques.isEmpty) {
      widgets.add(pw.Text(
        "Aucune rubrique (administration) configurée.",
        style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
      ));
    } else {
      final rowsRub = s.rubriques
          .map((r) => [
        r.rubrique,
        r.pourcentage > 0
            ? '${r.pourcentage.toStringAsFixed(0)}%'
            : '-',
        formatMontant(r.collecte),
        formatMontant(r.globales),
        formatMontant(r.independantes),
        formatMontant(r.mixtes),
        formatMontant(r.total),
        formatMontant(r.reste),
      ])
          .toList();
      widgets.add(
        pw.TableHelper.fromTextArray(
          headers: const [
            'Rubrique',
            'Taux',
            'Collecté (FC)',
            'Dép. globales',
            'Dép. indépendantes',
            'Dép. mixtes',
            'Total dépensé',
            'Reste (FC)',
          ],
          data: rowsRub,
          columnWidths: _buildColumnWidths([2.0, 0.7, 1.3, 1.2, 1.4, 1.2, 1.3, 1.3]),
          headerStyle: _pdfHeaderDepenseStyle(),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.red700),
          headerAlignment: pw.Alignment.center,
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          cellAlignment: pw.Alignment.centerRight,
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.center,
          },
          cellPadding:
          const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.red50),
        ),
      );
      final double totColl =
      s.rubriques.fold(0.0, (a, r) => a + r.collecte);
      final double totDep = s.rubriques.fold(0.0, (a, r) => a + r.total);
      widgets.add(pw.SizedBox(height: 3));
      widgets.add(pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          "TOTAL : collecté ${formatMontant(totColl)} FC  |  "
              "dépensé ${formatMontant(totDep)} FC  |  "
              "reste ${formatMontant(totColl - totDep)} FC",
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
      ));
    }
    widgets.add(pw.SizedBox(height: 12));

    widgets.add(pw.Text(
      "2. Par section — ${periodeCourte.toUpperCase()}",
      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
    ));
    widgets.add(pw.SizedBox(height: 4));
    final sectionsActives = s.sections.where((x) => x.aDeLActivite).toList();
    if (sectionsActives.isEmpty) {
      widgets.add(pw.Text(
        "Aucune activité (collecte ou dépense) par section sur cette période.",
        style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
      ));
    } else {
      final rowsSec = sectionsActives
          .map((x) => [
        x.section,
        formatMontant(x.collecte),
        formatMontant(x.independantes),
        formatMontant(x.mixtes),
        formatMontant(x.total),
        formatMontant(x.reste),
      ])
          .toList();
      widgets.add(
        pw.TableHelper.fromTextArray(
          headers: const [
            'Section',
            'Collecté (FC)',
            'Dép. indépendantes',
            'Dép. mixtes (part)',
            'Total dépensé',
            'Reste (FC)',
          ],
          data: rowsSec,
          columnWidths: _buildColumnWidths([2.2, 1.4, 1.5, 1.4, 1.4, 1.4]),
          headerStyle: _pdfHeaderDepenseStyle(),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.red700),
          headerAlignment: pw.Alignment.center,
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          cellAlignment: pw.Alignment.centerRight,
          cellAlignments: {0: pw.Alignment.centerLeft},
          cellPadding:
          const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.red50),
        ),
      );
    }
    if (!s.globalesExclues) {
      widgets.add(pw.SizedBox(height: 3));
      widgets.add(pw.Text(
        "Dépenses globales de l'école (non rattachées à une section) : "
            "${formatMontant(s.globales)} FC.",
        style: pw.TextStyle(
            fontSize: 9,
            fontStyle: pw.FontStyle.italic,
            color: PdfColors.grey800),
      ));
    }

    widgets.addAll(_buildDepensesParOptionTable(s));
    widgets.add(pw.SizedBox(height: 12));

    widgets.add(pw.Text(
      "3. Détail des dépenses (journal de caisse) — ${periodeCourte.toUpperCase()}",
      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
    ));
    widgets.add(pw.SizedBox(height: 4));
    if (s.depenses.isEmpty) {
      widgets.add(pw.Text(
        "Aucune dépense enregistrée sur cette période.",
        style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
      ));
    } else {
      final rowsDet = <List<String>>[];
      double totalListe = 0;
      for (var i = 0; i < s.depenses.length; i++) {
        final d = s.depenses[i];
        totalListe += d.montant;
        rowsDet.add([
          '${i + 1}',
          d.dateFormatee,
          d.porteeLabel,
          d.sectionsLabel,
          d.classesLabel,
          d.rubriqueAffichee,
          d.motif,
          formatMontant(d.montant),
          d.enregistrePar,
        ]);
      }
      widgets.add(
        pw.TableHelper.fromTextArray(
          headers: const [
            'N°',
            'Date et heure',
            'Type',
            'Section(s)',
            'Classe(s)',
            'Rubrique',
            'Motif / Explication',
            'Montant (FC)',
            'Enregistré par',
          ],
          data: rowsDet,
          columnWidths: _buildColumnWidths(
              [0.4, 1.5, 1.0, 1.4, 1.3, 1.3, 2.6, 1.1, 1.0]),
          headerStyle: _pdfHeaderDepenseStyle(),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.red700),
          headerAlignment: pw.Alignment.center,
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellAlignment: pw.Alignment.centerLeft,
          cellAlignments: {
            0: pw.Alignment.center,
            7: pw.Alignment.centerRight,
          },
          cellPadding:
          const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.red50),
        ),
      );
      widgets.add(pw.SizedBox(height: 3));
      widgets.add(pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          "TOTAL DES DÉPENSES LISTÉES : ${formatMontant(totalListe)} FC",
          style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
        ),
      ));
      if (s.globalesExclues) {
        widgets.add(pw.SizedBox(height: 2));
        widgets.add(pw.Text(
          "Note : les dépenses globales apparaissent dans cette liste mais "
              "ne sont pas déduites des montants de la section ci-dessus.",
          style: pw.TextStyle(
              fontSize: 8.5,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.grey700),
        ));
      }
    }

    widgets.add(pw.SizedBox(height: 10));
    widgets.add(
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          color: s.reste >= 0 ? PdfColors.green50 : PdfColors.red100,
          border: pw.Border.all(
            color: s.reste >= 0 ? PdfColors.green700 : PdfColors.red700,
            width: 1,
          ),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              "RESTE EN CAISSE APRÈS DÉPENSES $periodeCourte".toUpperCase(),
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              '${formatMontant(s.reste)} FC',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: s.reste >= 0 ? PdfColors.green800 : PdfColors.red800,
              ),
            ),
          ],
        ),
      ),
    );
    widgets.add(pw.SizedBox(height: 22));
    return widgets;
  }

  List<pw.Widget> _buildDepensesReportSections({
    String? sectionFilter,
    String? classFilter,
    String? mois,
  }) {
    final widgets = <pw.Widget>[
      pw.NewPage(),
      pw.Center(
        child: pw.Text(
          "RAPPORT DES DÉPENSES",
          style: pw.TextStyle(
            fontSize: 17,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.red800,
          ),
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Center(
        child: pw.Text(
          "${config.schoolName.toUpperCase()} — Année scolaire $currentYear",
          style: const pw.TextStyle(fontSize: 10.5, color: PdfColors.grey700),
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(9),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              "Comment lire ce rapport",
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              "• Dépense GLOBALE : elle concerne toute l'école (ex. : électricité, "
                  "frais administratifs généraux).",
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text(
              "• Dépense INDÉPENDANTE : elle concerne UNE seule section "
                  "(ex. : achat de craies pour la Maternelle).",
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text(
              "• Dépense MIXTE : elle concerne DEUX sections ou plus ; le montant "
                  "est réparti à parts égales entre les sections concernées.",
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text(
              "• Chaque dépense est imputée à une RUBRIQUE (salaire des "
                  "enseignants, construction, etc.) : le « Reste » est ce qui "
                  "demeure dans la rubrique après la sortie d'argent.",
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text(
              "• Chaque dépense apparaît dans le rapport correspondant à SA "
                  "PROPRE DATE (celle indiquée à l'enregistrement, ou "
                  "corrigée ensuite dans l'historique), et non à la date à "
                  "laquelle elle a été saisie dans l'application.",
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 14),
    ];

    // ⚡ NOUVEAU — rapport d'un mois choisi : on n'affiche que les dépenses
    // de ce mois.
    if (mois != null) {
      final stats = _computeDepensesStatsMois(
        mois,
        sectionFilter: sectionFilter,
        classFilter: classFilter,
      );
      widgets.addAll(_buildDepensesPeriodeSection(
        stats,
        sectionFilter: sectionFilter,
        titreForce:
        "DÉPENSES MENSUELLES — ${_libelleMoisCalendrier(mois)}",
      ));
      return widgets;
    }

    for (final period in const ['today', 'month', 'year']) {
      // ⚡ Collecte exprimée en montants de rapport si la fonction est active ;
      // sinon calcul d'origine inchangé.
      final stats = _rapportPersonnaliseEnVigueur
          ? _computeDepensesStatsRapport(
        period,
        sectionFilter: sectionFilter,
        classFilter: classFilter,
      )
          : computeDepensesStats(
        period,
        sectionFilter: sectionFilter,
        classFilter: classFilter,
      );
      widgets.addAll(_buildDepensesPeriodeSection(
        stats,
        sectionFilter: sectionFilter,
      ));
    }
    return widgets;
  }

  List<pw.Widget> _buildCenteredReportHeader({
    required String title,
    String? subtitle,
  }) {
    return [
      pw.Center(
        child: pw.Text(
          config.schoolName.toUpperCase(),
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Center(
        child: pw.Text(
          title,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
      ),
      if (subtitle != null && subtitle.trim().isNotEmpty) ...[
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            subtitle,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ),
      ],
      pw.SizedBox(height: 2),
      pw.Center(
        child: pw.Text(
          'Généré le : $_dateGenerationFormatee',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      ),
      pw.SizedBox(height: 16),
      pw.Divider(thickness: 1),
      pw.SizedBox(height: 10),
    ];
  }

  pw.Widget _pdfDetailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              "$label :",
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 11,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfTotalRow(String label, double amount, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          pw.Text(
            '${amount.toStringAsFixed(0)} FC',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfMonthRow(String mois, double paye, double requis) {
    final double reste = requis - paye;
    final bool nonCommence = paye == 0 && reste == requis;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              mois,
              style: pw.TextStyle(
                fontSize: 10.5,
                color: nonCommence ? PdfColors.grey600 : PdfColors.black,
                fontWeight:
                nonCommence ? pw.FontWeight.normal : pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              '${paye.toStringAsFixed(0)} / ${requis.toStringAsFixed(0)} FC',
              style: pw.TextStyle(
                fontSize: 10.5,
                color: nonCommence ? PdfColors.grey600 : PdfColors.black,
              ),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: reste <= 0
                  ? pw.Text(
                'OK',
                style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.green700,
                  fontWeight: pw.FontWeight.bold,
                ),
              )
                  : (nonCommence
                  ? pw.Text(
                '-',
                style: const pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey600),
              )
                  : pw.Text(
                '-${reste.toStringAsFixed(0)} FC',
                style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.orange800,
                  fontWeight: pw.FontWeight.bold,
                ),
              )),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfTransactionRow(Map<String, dynamic> t) {
    final date = t['date']?.toString() ?? '—';
    final mois = t['mois']?.toString() ?? '—';
    final amount = (t['amount'] as num?)?.toDouble() ?? 0.0;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              '$date  —  $mois',
              style: const pw.TextStyle(fontSize: 10.5),
            ),
          ),
          pw.Text(
            '${amount.toStringAsFixed(0)} FC',
            style: pw.TextStyle(
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ⚠️ REÇU / HISTORIQUE DE PAIEMENT : reste TOUJOURS sur les montants réels
  // (aucune conversion « montants du rapport » ici).
  Future<Map<String, dynamic>> generateStudentPaymentHistoryPdf({
    required Eleve eleve,
    String? filename,
  }) async {
    final pdf = pw.Document();

    final double totalPaye = getStudentTotalPaid(eleve);
    final double totalRequis = getStudentPending(eleve) + totalPaye;
    final double resteTotal = totalRequis - totalPaye;

    final sortedTransactions =
    List<Map<String, dynamic>>.from(eleve.transactions)
      ..sort((a, b) => (a['date'] ?? '')
          .toString()
          .compareTo((b['date'] ?? '').toString()));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          pw.Center(
            child: pw.Text(
              config.schoolName.toUpperCase(),
              textAlign: pw.TextAlign.center,
              style:
              pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              "REÇU DE PAIEMENT",
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 13,
                decoration: pw.TextDecoration.underline,
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              "Année scolaire : $currentYear",
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 10),

          _pdfDetailRow(
              "Nom complet", "${eleve.nom} ${eleve.postNom} ${eleve.prenom}"),
          _pdfDetailRow("ID", eleve.id.isNotEmpty ? eleve.id : "N/A"),
          _pdfDetailRow("Promotion", eleve.classe),
          _pdfDetailRow("Section", eleve.section),

          pw.SizedBox(height: 10),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 10),

          pw.Text(
            "BILAN FINANCIER",
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 13,
              color: PdfColors.indigo900,
            ),
          ),
          pw.SizedBox(height: 8),
          ...months.map((mois) {
            final requis = getRequiredForMonthForEleve(eleve, mois);
            final paye = (eleve.paid[mois] ?? 0).toDouble();
            return _pdfMonthRow(mois, paye, requis);
          }),

          pw.SizedBox(height: 10),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 10),

          _pdfTotalRow("Total payé", totalPaye, PdfColors.green700),
          _pdfTotalRow(
              "Total requis (annuel)", totalRequis, PdfColors.indigo900),
          _pdfTotalRow(
            "Reste à payer",
            resteTotal > 0 ? resteTotal : 0,
            resteTotal > 0 ? PdfColors.red700 : PdfColors.green700,
          ),

          pw.SizedBox(height: 10),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 10),

          pw.Text(
            "HISTORIQUE DES PAIEMENTS",
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 13,
              color: PdfColors.indigo900,
            ),
          ),
          pw.SizedBox(height: 8),
          if (sortedTransactions.isEmpty)
            pw.Text(
              "Aucune transaction enregistrée.",
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            )
          else
            ...sortedTransactions.map(_pdfTransactionRow),
        ],
      ),
    );

    final String safeFilename = (filename != null && filename.trim().isNotEmpty)
        ? filename.trim()
        : "${eleve.nom}_${eleve.postNom}_${eleve.id}"
        .replaceAll(RegExp(r'\s+'), '_');

    return await _savePdf(pdf, safeFilename, "historique_paiements");
  }

  Future<Map<String, dynamic>> printStudentPaymentHistoryReceipt({
    required Eleve eleve,
    bool duplicata = false,
  }) async {
    final String printerName = await _currentPrinterName();
    if (printerName.isEmpty) {
      return {
        'success': false,
        'error': "Aucune imprimante configurée. Configurez-la dans Paramètres.",
      };
    }

    final Uint8List? logoBytes = await _loadLogoBytesForPrinting();

    final Map<String, double> paidByMonth = {};
    final Map<String, double> requiredByMonth = {};
    for (final mois in months) {
      paidByMonth[mois] = (eleve.paid[mois] ?? 0).toDouble();
      requiredByMonth[mois] = getRequiredForMonthForEleve(eleve, mois);
    }

    final double totalPaye = getStudentTotalPaid(eleve);
    final double totalRequis = getStudentPending(eleve) + totalPaye;

    final List<Map<String, dynamic>> transactions = eleve.transactions
        .map((t) => Map<String, dynamic>.from(t))
        .toList();

    final bool ok = await EscPosPrinterService.printStudentPaymentHistoryReceipt(
      printerName: printerName,
      schoolName: config.schoolName,
      currentYear: currentYear,
      studentName: '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      studentId: eleve.id.isNotEmpty ? eleve.id : "N/A",
      classe: eleve.classe,
      section: eleve.section,
      months: months,
      paidByMonth: paidByMonth,
      requiredByMonth: requiredByMonth,
      totalPaye: totalPaye,
      totalRequis: totalRequis,
      transactions: transactions,
      logoBytes: logoBytes,
      duplicata: duplicata,
    );

    if (!ok) {
      return {
        'success': false,
        'error': "Échec de l'impression. Vérifiez l'imprimante.",
      };
    }
    return {'success': true};
  }

  Future<Map<String, dynamic>> generatePdf({
    required String filename,
    required String reportType,
    String? sectionFilter,
    String? classFilter,
    String? city,
    bool includeDepenses = true,
    String? mois, // ⚡ NOUVEAU — mois scolaire choisi (rapport mensuel)
  }) async {
    // ⚡ NOUVEAU — s'assure que le réglage « montants personnalisés » est
    // chargé (sans effet s'il n'a jamais été activé).
    await rapportPersonnalise.charger();

    if (reportType == "student_list") {
      return await _generateStudentListPdf(
        filename:      filename,
        sectionFilter: sectionFilter,
        classFilter:   classFilter,
        city:          city,
      );
    }

    // ⚡ NOUVEAU — le mois choisi n'a de sens que pour le rapport mensuel.
    final String? moisSel = (reportType == "monthly" &&
        mois != null &&
        mois.trim().isNotEmpty &&
        months.contains(mois))
        ? mois
        : null;

    final String periodePourMontant = reportType == "daily"
        ? "today"
        : (reportType == "monthly" ? "month" : "year");

    final pdf     = pw.Document();
    List<Eleve> students;
    String title;
    String countLabel;

    if (reportType == "daily") {
      students = getPaidStudentsToday();
      title    = "RAPPORT JOURNALIER";
      countLabel = "ont payé aujourd'hui";
    } else if (reportType == "monthly") {
      if (moisSel != null) {
        students = _elevesAyantPayeMois(moisSel);
        title    = "RAPPORT MENSUEL — ${moisSel.toUpperCase()}";
        countLabel = "ont payé pour le mois de $moisSel";
      } else {
        students = getPaidStudentsThisMonth();
        title    = "RAPPORT MENSUEL";
        countLabel = "ont payé ce mois-ci";
      }
    } else {
      students = currentData.eleves;
      title    = "RAPPORT ANNUEL";
      countLabel = "figurent dans ce rapport";
    }

    final List<Eleve> studentsAvantFiltres = List<Eleve>.from(students);
    final bool afficherRepartitionParSection =
        sectionFilter == null && classFilter == null;

    if (sectionFilter != null) {
      students = students
          .where((e) => e.section == sectionFilter)
          .toList();
      title += " - $sectionFilter";
    }
    if (classFilter != null) {
      students = students
          .where((e) => e.classe == classFilter)
          .toList();
      title += " - $classFilter";
    }

    final double total              = students.fold(
        0.0, (sum, e) => sum + _montantEleve(e, periodePourMontant, moisSel));
    final adminDistribution         = calculateAdminDistribution(total);
    // ⚡ Totaux de l'école exprimés en montants de rapport si la fonction est
    // active (sinon : mêmes valeurs qu'avant).
    final double totalMoisEcole     = moisSel != null
        ? _totalCollecteMois(moisSel)
        : _totalMoisCourantRapport();
    final double totalAnneeEcole    = _totalAnneeRapport();
    final double totalDepensesAnnee = getTotalDepenses();
    final double soldeNetAnnee      = totalAnneeEcole - totalDepensesAnnee;
    final String currentMonthName = moisSel != null
        ? _libelleMoisCalendrier(moisSel)
        : (currentSchoolMonthName ?? "Hors année scolaire (vacances)");
    final bool showMoisConcerne = reportType == "daily";

    final headers = [
      'ID', 'Nom Complet', 'Section', 'Classe', 'Montant Payé (FC)',
      if (showMoisConcerne) 'Mois Concerné(s)',
      ...config.administrations.map(
              (a) => '${a.nom} (${a.pourcentage.toStringAsFixed(0)}%)'),
    ];

    final List<Eleve> studentsTriesPourListe = List<Eleve>.from(students);
    int indexSectionPourTri(String section) {
      final i = config.sections.indexOf(section);
      return i < 0 ? (1 << 20) : i;
    }

    int indexClassePourTri(Eleve e) {
      final liste = config.classesBySection[e.section];
      if (liste == null) return 1 << 20;
      final i = liste.indexOf(classeNumeroFromFullClasse(e.classe));
      return i < 0 ? (1 << 20) : i;
    }

    studentsTriesPourListe.sort((a, b) {
      int c = indexSectionPourTri(a.section)
          .compareTo(indexSectionPourTri(b.section));
      if (c != 0) return c;
      c = a.section.toLowerCase().compareTo(b.section.toLowerCase());
      if (c != 0) return c;
      c = indexClassePourTri(a).compareTo(indexClassePourTri(b));
      if (c != 0) return c;
      c = a.classe.toLowerCase().compareTo(b.classe.toLowerCase());
      if (c != 0) return c;
      c = a.nom.toLowerCase().compareTo(b.nom.toLowerCase());
      if (c != 0) return c;
      c = a.postNom.toLowerCase().compareTo(b.postNom.toLowerCase());
      if (c != 0) return c;
      return a.prenom.toLowerCase().compareTo(b.prenom.toLowerCase());
    });

    final rows = studentsTriesPourListe.map((e) {
      final montant = _montantEleve(e, periodePourMontant, moisSel);
      final row = [
        e.id.isNotEmpty ? e.id : "N/A",
        "${e.nom} ${e.postNom} ${e.prenom}",
        e.section,
        e.classe,
        montant.toStringAsFixed(0),
      ];
      if (showMoisConcerne) {
        final moisConcernes = getMoisPayesPourDate(e);
        row.add(moisConcernes.isNotEmpty
            ? moisConcernes
            : (currentSchoolMonthName ?? '-'));
      }
      for (var admin in config.administrations) {
        row.add(
            (montant * (admin.pourcentage / 100)).toStringAsFixed(0));
      }
      return row;
    }).toList();
    final List<double> recapMensuel =
    reportType == "annual" ? _evolutionMensuelleRapport() : const [];

    final List<double> mainTableFlex = [
      0.7,
      2.5,
      1.1,
      1.3,
      1.3,
      if (showMoisConcerne) 1.7,
      ...List<double>.filled(config.administrations.length, 1.3),
    ];
    final mainTableColumnWidths = _buildColumnWidths(mainTableFlex);
    final double mainCellFontSize = _tableCellFontSize(headers.length);
    final double mainHeaderFontSize = _tableHeaderFontSize(headers.length);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) => [
          ..._buildCenteredReportHeader(
            title: title,
            subtitle: 'Année scolaire $currentYear',
          ),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.indigo50,
              border: pw.Border.all(color: PdfColors.indigo200, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "Total Collecté (ce rapport) : ${total.toStringAsFixed(0)} FC",
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.indigo900,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  "Total ce Mois ($currentMonthName) : "
                      "${totalMoisEcole.toStringAsFixed(0)} FC",
                  style: const pw.TextStyle(fontSize: 11),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  "Total cette Année ($currentYear) : "
                      "${totalAnneeEcole.toStringAsFixed(0)} FC",
                  style: const pw.TextStyle(fontSize: 11),
                ),
                if (includeDepenses) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    "Total des dépenses de l'année (toute l'école) : "
                        "${formatMontant(totalDepensesAnnee)} FC",
                    style: const pw.TextStyle(
                        fontSize: 11, color: PdfColors.red800),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    "Solde net de l'année après dépenses : "
                        "${formatMontant(soldeNetAnnee)} FC "
                        "(détail des dépenses en fin de rapport)",
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.indigo900,
                    ),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          ..._buildStudentCountSection(students, label: countLabel),
          pw.SizedBox(height: 16),
          pw.Text("LISTE DES ÉLÈVES",
              style: pw.TextStyle(
                  fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers:   headers,
            data:      rows,
            columnWidths: mainTableColumnWidths,
            headerStyle: pw.TextStyle(
                fontSize: mainHeaderFontSize,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white),
            headerDecoration:
            const pw.BoxDecoration(color: PdfColors.indigo),
            cellStyle: pw.TextStyle(fontSize: mainCellFontSize),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding:
            const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            oddRowDecoration:
            const pw.BoxDecoration(color: PdfColors.indigo50),
          ),
          if (reportType == "annual") ...[
            pw.SizedBox(height: 26),
            pw.Text("RÉCAPITULATIF MENSUEL",
                style: pw.TextStyle(
                    fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: const ['Mois', 'Total Collecté (FC)'],
              data: List<List<String>>.generate(
                months.length,
                    (i) => [
                  months[i],
                  (i < recapMensuel.length ? recapMensuel[i] : 0.0)
                      .toStringAsFixed(0),
                ],
              ),
              columnWidths: _buildColumnWidths([1.4, 1]),
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration:
              const pw.BoxDecoration(color: PdfColors.indigo),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding:
              const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
              },
              oddRowDecoration:
              const pw.BoxDecoration(color: PdfColors.indigo50),
            ),
          ],
          pw.SizedBox(height: 30),
          if (afficherRepartitionParSection)
            ..._buildRepartitionParSectionEtAdministration(
                studentsAvantFiltres, periodePourMontant, moisSel),
          pw.Text(
            "RÉPARTITION GLOBALE PAR ADMINISTRATION",
            style: pw.TextStyle(
                fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          ...adminDistribution.entries.map(
                (entry) => pw.Text(
              "${entry.key} : ${entry.value.toStringAsFixed(0)} FC "
                  "(${config.administrations.firstWhere((a) => a.nom == entry.key).pourcentage.toStringAsFixed(0)}%)",
            ),
          ),

          if (includeDepenses)
            ..._buildDepensesReportSections(
              sectionFilter: sectionFilter,
              classFilter: classFilter,
              mois: moisSel,
            ),

          ..._buildSignatureSection(city),
        ],
      ),
    );

    return await _savePdf(pdf, filename, reportType);
  }

  Future<Map<String, dynamic>> _generateStudentListPdf({
    required String filename,
    String? sectionFilter,
    String? classFilter,
    String? city,
  }) async {
    List<Eleve> students = currentData.eleves;
    if (sectionFilter != null) {
      students =
          students.where((e) => e.section == sectionFilter).toList();
    }
    if (classFilter != null) {
      students =
          students.where((e) => e.classe == classFilter).toList();
    }
    students.sort((a, b) {
      final c = a.classe.compareTo(b.classe);
      if (c != 0) return c;
      return a.nom.compareTo(b.nom);
    });

    final sectionLabel = sectionFilter ?? "Toutes les sections";
    final classeLabel  = classFilter   ?? "Toutes les classes";
    final dateStr      = _dateGenerationFormatee;

    final rows = <List<String>>[];
    for (int i = 0; i < students.length; i++) {
      final e = students[i];
      rows.add(['${i + 1}', e.nom, e.postNom, e.prenom, e.classe]);
    }

    final columnWidths = _buildColumnWidths([0.5, 1.6, 1.6, 1.6, 1.5]);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) => [
          pw.Center(
            child: pw.Text(
              config.schoolName.toUpperCase(),
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              "REGISTRE DES ÉLÈVES — Année $currentYear",
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              "Section : $sectionLabel | Classe : $classeLabel",
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              "Imprimé le : $dateStr | Total : ${students.length} élève(s)",
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey700),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['N°', 'Nom', 'Post-nom', 'Prénom', 'Classe'],
            data:    rows,
            columnWidths: columnWidths,
            headerStyle: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration:
            const pw.BoxDecoration(color: PdfColors.indigo),
            cellStyle:   const pw.TextStyle(fontSize: 10),
            cellHeight:  22,
            cellPadding:
            const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.centerLeft,
            },
            oddRowDecoration:
            const pw.BoxDecoration(color: PdfColors.indigo50),
          ),
          ..._buildSignatureSection(city),
        ],
      ),
    );

    return await _savePdf(pdf, filename, "student_list");
  }

  Future<Map<String, dynamic>> generateOrderStatusPdf({
    required String filename,
    required String mois,
    required bool enOrdre,
    String? sectionFilter,
    String? classFilter,
  }) async {
    // ⚡ NOUVEAU — chargement du réglage « montants personnalisés ».
    await rapportPersonnalise.charger();

    final students = getStudentsByOrderStatus(
      mois:          mois,
      enOrdre:       enOrdre,
      sectionFilter: sectionFilter,
      classFilter:   classFilter,
    );

    final sectionLabel = sectionFilter ?? "Toutes les sections";
    final classeLabel  = classFilter   ?? "Toutes les classes";
    final dateStr      = _dateGenerationFormatee;
    final statutLabel  =
    enOrdre ? "QUI ONT DÉJÀ PAYÉ" : "QUI N'ONT PAS ENCORE PAYÉ";

    final title = "LISTE DES ÉLÈVES DE $classeLabel - $sectionLabel "
        "DU $dateStr $statutLabel $mois";

    final rows = <List<String>>[];
    for (int i = 0; i < students.length; i++) {
      final e              = students[i];
      // ⚡ Montants exprimés en montants de rapport si la fonction est active
      // (payé ET requis convertis avec le même coefficient : le statut
      // « en ordre » reste cohérent).
      final montantPaye    =
      _versMontantRapportEleve(e, e.paid[mois] ?? 0.0);
      final montantRequis  = _versMontantRapportEleve(
          e, getRequiredForMonthForEleve(e, mois));
      rows.add([
        '${i + 1}',
        e.nom,
        e.postNom,
        e.prenom,
        e.section,
        e.classe,
        '${montantPaye.toStringAsFixed(0)} / ${montantRequis.toStringAsFixed(0)} FC',
      ]);
    }

    final columnWidths =
    _buildColumnWidths([0.5, 1.4, 1.4, 1.4, 1.1, 1.3, 1.8]);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) => [
          pw.Center(
            child: pw.Text(
              config.schoolName.toUpperCase(),
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              title,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              "Section : $sectionLabel | Classe : $classeLabel | Mois : $mois",
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              "Année $currentYear | Imprimé le : $dateStr | "
                  "Total : ${students.length} élève(s)",
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey700),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: [
              'N°', 'Nom', 'Post-nom', 'Prénom', 'Section', 'Classe',
              'Payé / Requis ($mois)',
            ],
            data: rows,
            columnWidths: columnWidths,
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: pw.BoxDecoration(
              color: enOrdre ? PdfColors.green700 : PdfColors.red700,
            ),
            cellStyle:  const pw.TextStyle(fontSize: 9),
            cellHeight: 22,
            cellPadding:
            const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.centerLeft,
              5: pw.Alignment.centerLeft,
              6: pw.Alignment.center,
            },
            oddRowDecoration: pw.BoxDecoration(
              color: enOrdre ? PdfColors.green50 : PdfColors.red50,
            ),
          ),
        ],
      ),
    );

    return await _savePdf(
      pdf,
      filename,
      enOrdre ? 'en_ordre_$mois' : 'pas_en_ordre_$mois',
    );
  }

  bool _estEleveArchive(Eleve e) =>
      !currentData.eleves.any((x) => x.id == e.id) &&
          elevesSupprimesData.eleves.any((x) => x.id == e.id);

  String _libelleTranchePaiement(AutreFraisPaiement p, Eleve? eleve) {
    if (p.trancheId.isNotEmpty) {
      final String l = p.trancheLibelle;
      return l.isNotEmpty ? l : 'Tranche ${p.trancheNumero}';
    }
    if (eleve == null) return 'Paiement unique';
    AutreFrais? frais;
    for (final f in autresFrais) {
      if (f.id == p.autreFraisId) {
        frais = f;
        break;
      }
    }
    if (frais == null) return 'Paiement unique';
    final tranches = getTranchesPourEleve(frais, eleve);
    if (tranches.isEmpty) return 'Paiement unique';
    double cumul = 0;
    int k = 0;
    for (final t in tranches) {
      cumul += t.montant;
      if (p.montant + 0.5 >= cumul) {
        k++;
      } else {
        break;
      }
    }
    return k > 0
        ? 'Avant tranches (couvre $k/${tranches.length})'
        : 'Avant tranches (partiel)';
  }

  bool _libelleEstTranche(String l) =>
      l != 'Paiement unique' && l != '-' && l.isNotEmpty;

  // ==========================================================================
  // ⚡ CORRECTION — NOM DE FICHIER DES RAPPORTS "AUTRES FRAIS"
  // --------------------------------------------------------------------------
  // Avant : le nom du fichier PDF ne contenait pas le type de frais. Deux
  // frais différents (ex : "Frais de l'État" puis "Frais de bibliothèque")
  // produisaient donc EXACTEMENT le même nom de fichier : le second rapport
  // écrasait le premier, comme une "mise à jour".
  //
  // Maintenant : le nom du type de frais est inclus dans le nom du fichier.
  //   - même type de frais, même période, même jour -> même fichier
  //     (le rapport est simplement mis à jour / régénéré) ;
  //   - type de frais différent -> nouveau fichier, l'ancien reste intact.
  // ==========================================================================
  String _nomFichierSur(String texte) {
    final String propre = texte
        .trim()
        .replaceAll(RegExp(r"[’'`]"), '')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    return propre.isEmpty ? 'Frais' : propre;
  }

  Future<Map<String, dynamic>> generateAutresFraisPdf({
    required String filename,
    String? autreFraisId,
    String? autreFraisGroupeCle,
    String? sectionFilter,
    String? classFilter,
    String? city,
    String periode = 'year',
    String? mois, // ⚡ NOUVEAU — mois scolaire choisi (période 'month')
  }) async {
    final String? moisSel =
    (periode == 'month' && mois != null && months.contains(mois))
        ? mois
        : null;

    String? cleGroupe = autreFraisGroupeCle;
    if (cleGroupe == null && autreFraisId != null) {
      for (final f in autresFrais) {
        if (f.id == autreFraisId) {
          cleGroupe = normaliserNomFrais(f.nom);
          break;
        }
      }
    }

    AutreFraisGroupe? groupe;
    if (cleGroupe != null) {
      for (final g in getAutresFraisGroupes()) {
        if (g.cle == cleGroupe) {
          groupe = g;
          break;
        }
      }
    }

    final Set<String> idsGroupe = {
      if (groupe != null) ...groupe.ids,
      if (autreFraisId != null) autreFraisId,
    };
    final bool modeFusion = cleGroupe != null || autreFraisId != null;

    List<AutreFraisPaiement> paiementsAnnee = getAutresFraisPaiementsForYear();
    if (modeFusion) {
      final String? cleFinale = cleGroupe;
      paiementsAnnee = paiementsAnnee.where((p) {
        if (idsGroupe.contains(p.autreFraisId)) return true;
        if (cleFinale != null &&
            normaliserNomFrais(p.autreFraisNom) == cleFinale) {
          return true;
        }
        return false;
      }).toList();
    }

    final List<AutreFraisPaiement> paiements = paiementsAnnee
        .where((p) => _paiementAutreFraisDansPeriodeMois(p, periode, moisSel))
        .toList();

    final Map<String, List<AutreFraisPaiement>> paiementsAnneeParEleve = {};
    for (final p in paiementsAnnee) {
      paiementsAnneeParEleve.putIfAbsent(p.eleveId, () => []).add(p);
    }

    final Map<String, Eleve?> cacheEleves = {};
    Eleve? chercherEleve(String id) {
      if (!cacheEleves.containsKey(id)) {
        cacheEleves[id] = trouverEleveParId(id);
      }
      return cacheEleves[id];
    }

    int indexSectionPourTri(String section) {
      final i = config.sections.indexOf(section);
      return i < 0 ? (1 << 20) : i;
    }

    int indexClassePourTri(String section, String classe) {
      final liste = config.classesBySection[section];
      if (liste == null) return 1 << 20;
      final i = liste.indexOf(classeNumeroFromFullClasse(classe));
      return i < 0 ? (1 << 20) : i;
    }

    final List<Map<String, dynamic>> entrees = [];
    double total = 0;
    final Map<String, Eleve> elevesDistincts = {};

    for (final p in paiements) {
      final Eleve? eleve = chercherEleve(p.eleveId);
      final section = eleve?.section ?? '';
      final classe  = eleve?.classe  ?? '';
      if (sectionFilter != null && section != sectionFilter) continue;
      if (classFilter != null && classe != classFilter) continue;

      entrees.add({
        'p': p,
        'eleve': eleve,
        'section': section,
        'classe': classe,
        'tranche': _libelleTranchePaiement(p, eleve),
      });
      total += p.montant;
      if (eleve != null) {
        elevesDistincts[eleve.id] = eleve;
      }
    }

    final bool aDesTranches =
    entrees.any((en) => _libelleEstTranche(en['tranche'] as String));

    if (modeFusion) {
      entrees.sort((a, b) {
        final String sa = a['section'] as String;
        final String sb = b['section'] as String;
        final String ca = a['classe'] as String;
        final String cb = b['classe'] as String;
        int c = indexSectionPourTri(sa).compareTo(indexSectionPourTri(sb));
        if (c != 0) return c;
        c = sa.toLowerCase().compareTo(sb.toLowerCase());
        if (c != 0) return c;
        c = indexClassePourTri(sa, ca).compareTo(indexClassePourTri(sb, cb));
        if (c != 0) return c;
        c = ca.toLowerCase().compareTo(cb.toLowerCase());
        if (c != 0) return c;
        final Eleve? ea = a['eleve'] as Eleve?;
        final Eleve? eb = b['eleve'] as Eleve?;
        final String na = ea != null
            ? '${ea.nom} ${ea.postNom} ${ea.prenom}'.toLowerCase()
            : '~';
        final String nb = eb != null
            ? '${eb.nom} ${eb.postNom} ${eb.prenom}'.toLowerCase()
            : '~';
        c = na.compareTo(nb);
        if (c != 0) return c;
        final AutreFraisPaiement pa = a['p'] as AutreFraisPaiement;
        final AutreFraisPaiement pb = b['p'] as AutreFraisPaiement;
        c = pa.trancheNumero.compareTo(pb.trancheNumero);
        if (c != 0) return c;
        return pa.date.compareTo(pb.date);
      });
    }

    final rows = <List<String>>[];
    for (final en in entrees) {
      final AutreFraisPaiement p = en['p'] as AutreFraisPaiement;
      final Eleve? eleve = en['eleve'] as Eleve?;
      final String section = en['section'] as String;
      final String classe = en['classe'] as String;
      final String tranche = en['tranche'] as String;
      String nomEleve;
      if (eleve == null) {
        nomEleve = "Élève introuvable";
      } else {
        nomEleve = "${eleve.nom} ${eleve.postNom} ${eleve.prenom}";
        if (_estEleveArchive(eleve)) nomEleve += " (supprimé)";
      }
      rows.add([
        (eleve != null && eleve.id.isNotEmpty) ? eleve.id : 'N/A',
        nomEleve,
        section.isEmpty ? '-' : section,
        classe.isEmpty ? '-' : classe,
        p.autreFraisNom,
        tranche.isEmpty ? '-' : tranche,
        p.montant.toStringAsFixed(0),
        p.dateFormatee,
      ]);
    }

    final adminDistribution = calculateAutresFraisAdminDistribution(total);

    final List<pw.Widget> recapWidgets = [];
    int totalConcernes = 0;
    int totalSoldes = 0;
    int totalPartiels = 0;

    if (modeFusion) {
      String cleSC(String s, String c) => '$s\u0001$c';

      final Map<String, String> sectionDeCle = {};
      final Map<String, String> classeDeCle = {};
      final Map<String, Set<String>> concernesParCle = {};
      final Map<String, Set<String>> soldesParCle = {};
      final Map<String, Set<String>> partielsParCle = {};
      final Map<String, double> totalParCle = {};
      final Map<String, Set<double>> montantsParCle = {};

      void assurerCle(String k, String s, String c) {
        sectionDeCle.putIfAbsent(k, () => s);
        classeDeCle.putIfAbsent(k, () => c);
        concernesParCle.putIfAbsent(k, () => <String>{});
        soldesParCle.putIfAbsent(k, () => <String>{});
        partielsParCle.putIfAbsent(k, () => <String>{});
        totalParCle.putIfAbsent(k, () => 0.0);
        montantsParCle.putIfAbsent(k, () => <double>{});
      }

      for (final en in entrees) {
        final AutreFraisPaiement p = en['p'] as AutreFraisPaiement;
        final String s0 = en['section'] as String;
        final String c0 = en['classe'] as String;
        final String s = s0.isEmpty ? '-' : s0;
        final String c = c0.isEmpty ? '-' : c0;
        final String k = cleSC(s, c);
        assurerCle(k, s, c);
        concernesParCle[k]!.add(p.eleveId);
        totalParCle[k] = (totalParCle[k] ?? 0) + p.montant;
        montantsParCle[k]!.add(p.montant);
      }

      final fraisDuGroupe =
      autresFrais.where((f) => idsGroupe.contains(f.id)).toList();

      AutreFrais? fraisApplicablePour(Eleve e) {
        for (final f in fraisDuGroupe) {
          if (autreFraisAppliesToStudent(f, e)) return f;
        }
        return null;
      }

      void classer(String k, Eleve e, AutreFrais f) {
        final liste = paiementsAnneeParEleve[e.id] ?? const <AutreFraisPaiement>[];
        if (liste.isEmpty) return;
        final statut = getStatutAutreFrais(f, e, paiements: liste);
        if (statut.solde) {
          soldesParCle[k]!.add(e.id);
        } else {
          partielsParCle[k]!.add(e.id);
        }
      }

      final Set<String> elevesExamines = {};
      for (final e in currentData.eleves) {
        if (sectionFilter != null && e.section != sectionFilter) continue;
        if (classFilter != null && e.classe != classFilter) continue;
        final AutreFrais? fraisApplicable = fraisApplicablePour(e);
        if (fraisApplicable == null) continue;
        final String k = cleSC(e.section, e.classe);
        assurerCle(k, e.section, e.classe);
        concernesParCle[k]!.add(e.id);
        montantsParCle[k]!
            .add(getMontantAutreFraisPourEleve(fraisApplicable, e));
        elevesExamines.add(e.id);
        classer(k, e, fraisApplicable);
      }

      final Set<String> payeursVus = {};
      for (final en in entrees) {
        final AutreFraisPaiement p = en['p'] as AutreFraisPaiement;
        if (elevesExamines.contains(p.eleveId)) continue;
        if (!payeursVus.add(p.eleveId)) continue;
        final String s0 = en['section'] as String;
        final String c0 = en['classe'] as String;
        final String k = cleSC(s0.isEmpty ? '-' : s0, c0.isEmpty ? '-' : c0);
        final Eleve? e = en['eleve'] as Eleve?;
        final AutreFrais? f = e != null ? fraisApplicablePour(e) : null;
        if (e != null && f != null) {
          classer(k, e, f);
        } else {
          soldesParCle[k]?.add(p.eleveId);
        }
      }

      String montantLabel(Set<double> s) {
        if (s.isEmpty) return '-';
        final l = s.toList()..sort();
        if ((l.last - l.first).abs() < 0.5) return formatMontant(l.first);
        return '${formatMontant(l.first)} - ${formatMontant(l.last)}';
      }

      final List<String> cles = sectionDeCle.keys.toList();
      cles.sort((a, b) {
        final String sa = sectionDeCle[a]!;
        final String sb = sectionDeCle[b]!;
        final String ca = classeDeCle[a]!;
        final String cb = classeDeCle[b]!;
        int c = indexSectionPourTri(sa).compareTo(indexSectionPourTri(sb));
        if (c != 0) return c;
        c = sa.toLowerCase().compareTo(sb.toLowerCase());
        if (c != 0) return c;
        c = indexClassePourTri(sa, ca).compareTo(indexClassePourTri(sb, cb));
        if (c != 0) return c;
        return ca.toLowerCase().compareTo(cb.toLowerCase());
      });

      final rowsClasse = <List<String>>[];
      int sumConc = 0;
      int sumSolde = 0;
      int sumPartiel = 0;
      double sumTot = 0;
      for (final k in cles) {
        final int conc = concernesParCle[k]!.length;
        final int sold = soldesParCle[k]!.length;
        final int part = partielsParCle[k]!.length;
        final double tot = totalParCle[k] ?? 0;
        if (conc == 0 && sold == 0 && part == 0) continue;
        final int reste = conc - sold - part < 0 ? 0 : conc - sold - part;
        sumConc += conc;
        sumSolde += sold;
        sumPartiel += part;
        sumTot += tot;
        rowsClasse.add([
          sectionDeCle[k]!,
          classeDeCle[k]!,
          montantLabel(montantsParCle[k]!),
          '$conc',
          '$sold',
          '$part',
          '$reste',
          formatMontant(tot),
        ]);
      }
      totalConcernes = sumConc;
      totalSoldes = sumSolde;
      totalPartiels = sumPartiel;
      final int sumReste =
      sumConc - sumSolde - sumPartiel < 0 ? 0 : sumConc - sumSolde - sumPartiel;
      rowsClasse.add([
        'TOTAL',
        '',
        '',
        '$sumConc',
        '$sumSolde',
        '$sumPartiel',
        '$sumReste',
        formatMontant(sumTot),
      ]);

      final List<String> sectionsVues = [];
      for (final k in cles) {
        final s = sectionDeCle[k]!;
        if (!sectionsVues.contains(s)) sectionsVues.add(s);
      }
      final rowsSection = <List<String>>[];
      for (final s in sectionsVues) {
        int conc = 0;
        int sold = 0;
        int part = 0;
        double tot = 0;
        final Set<double> montantsSection = {};
        for (final k in cles) {
          if (sectionDeCle[k] != s) continue;
          conc += concernesParCle[k]!.length;
          sold += soldesParCle[k]!.length;
          part += partielsParCle[k]!.length;
          tot += totalParCle[k] ?? 0;
          montantsSection.addAll(montantsParCle[k]!);
        }
        if (conc == 0 && sold == 0 && part == 0) continue;
        final int reste = conc - sold - part < 0 ? 0 : conc - sold - part;
        rowsSection.add([
          s,
          montantLabel(montantsSection),
          '$conc',
          '$sold',
          '$part',
          '$reste',
          formatMontant(tot),
        ]);
      }
      rowsSection.add([
        'TOTAL',
        '',
        '$sumConc',
        '$sumSolde',
        '$sumPartiel',
        '$sumReste',
        formatMontant(sumTot),
      ]);

      recapWidgets.addAll([
        pw.Text(
          "1. RÉCAPITULATIF PAR SECTION",
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          "Les montants peuvent différer d'une section à l'autre : ils sont "
              "rassemblés ici sous un seul et même type de frais. "
              "« Ont tout payé » = toutes les tranches couvertes (ou paiement "
              "unique) ; « Paiement partiel » = au moins un paiement mais "
              "pas toutes les tranches. Ces statuts tiennent compte de tous "
              "les paiements de l'année ; « Total collecté » ne compte que "
              "la période du rapport.",
          style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: const [
            'Section',
            'Montant unitaire (FC)',
            'Élèves concernés',
            'Ont tout payé',
            'Paiement partiel',
            'Pas encore payé',
            'Total collecté (FC)',
          ],
          data: rowsSection,
          columnWidths:
          _buildColumnWidths([2.2, 1.6, 1.2, 1.0, 1.1, 1.3, 1.6]),
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo800),
          headerAlignment: pw.Alignment.center,
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignment: pw.Alignment.center,
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            6: pw.Alignment.centerRight,
          },
          cellPadding:
          const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.indigo50),
        ),
        pw.SizedBox(height: 18),
        pw.Text(
          "2. RÉCAPITULATIF PAR CLASSE",
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          "Pour chaque classe : le montant à payer, le nombre d'élèves "
              "concernés, ceux qui ont tout payé, ceux qui n'ont payé qu'une "
              "partie (tranches), ceux qui n'ont pas encore payé, et le "
              "total collecté sur la période.",
          style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: const [
            'Section',
            'Classe',
            'Montant unitaire (FC)',
            'Élèves concernés',
            'Ont tout payé',
            'Paiement partiel',
            'Pas encore payé',
            'Total collecté (FC)',
          ],
          data: rowsClasse,
          columnWidths:
          _buildColumnWidths([1.8, 1.4, 1.6, 1.2, 1.0, 1.1, 1.3, 1.6]),
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
          headerAlignment: pw.Alignment.center,
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignment: pw.Alignment.center,
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            7: pw.Alignment.centerRight,
          },
          cellPadding:
          const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.indigo50),
        ),
        pw.SizedBox(height: 24),
      ]);

      if (aDesTranches) {
        final Map<String, Map<String, dynamic>> parTranche = {};
        for (final en in entrees) {
          final AutreFraisPaiement p = en['p'] as AutreFraisPaiement;
          final String libelle = en['tranche'] as String;
          if (!_libelleEstTranche(libelle)) continue;
          final String s0 = en['section'] as String;
          final String c0 = en['classe'] as String;
          final String s = s0.isEmpty ? '-' : s0;
          final String c = c0.isEmpty ? '-' : c0;
          final String k = '${cleSC(s, c)}\u0002${p.trancheNumero}\u0002$libelle';
          final d = parTranche.putIfAbsent(k, () => {
            'section': s,
            'classe': c,
            'numero': p.trancheNumero,
            'nom': libelle,
            'montants': <double>{},
            'eleves': <String>{},
            'total': 0.0,
          });
          (d['montants'] as Set<double>).add(p.montant);
          (d['eleves'] as Set<String>).add(p.eleveId);
          d['total'] = (d['total'] as double) + p.montant;
        }

        final listeTr = parTranche.values.toList();
        listeTr.sort((a, b) {
          final String sa = a['section'] as String;
          final String sb = b['section'] as String;
          final String ca = a['classe'] as String;
          final String cb = b['classe'] as String;
          int c = indexSectionPourTri(sa).compareTo(indexSectionPourTri(sb));
          if (c != 0) return c;
          c = sa.toLowerCase().compareTo(sb.toLowerCase());
          if (c != 0) return c;
          c = indexClassePourTri(sa, ca).compareTo(indexClassePourTri(sb, cb));
          if (c != 0) return c;
          c = ca.toLowerCase().compareTo(cb.toLowerCase());
          if (c != 0) return c;
          return (a['numero'] as int).compareTo(b['numero'] as int);
        });

        final rowsTr = <List<String>>[];
        double sumTrTotal = 0;
        int sumTrPaiements = 0;
        for (final d in listeTr) {
          final int nb = (d['eleves'] as Set<String>).length;
          sumTrPaiements += nb;
          sumTrTotal += d['total'] as double;
          rowsTr.add([
            d['section'] as String,
            d['classe'] as String,
            d['nom'] as String,
            montantLabel(d['montants'] as Set<double>),
            '$nb',
            formatMontant(d['total'] as double),
          ]);
        }
        rowsTr.add([
          'TOTAL',
          '',
          '',
          '',
          '$sumTrPaiements',
          formatMontant(sumTrTotal),
        ]);

        recapWidgets.addAll([
          pw.Text(
            "3. RÉCAPITULATIF PAR TRANCHE",
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            "Pour chaque section et classe : combien d'élèves ont payé "
                "chaque tranche, le montant versé et le total collecté. "
                "« Avant tranches » regroupe les paiements faits avant la "
                "création des tranches : leur montant d'origine est conservé.",
            style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Section',
              'Classe',
              'Tranche',
              'Montant versé (FC)',
              'Élèves ayant payé',
              'Total collecté (FC)',
            ],
            data: rowsTr,
            columnWidths: _buildColumnWidths([1.8, 1.4, 2.2, 1.6, 1.2, 1.6]),
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration:
            const pw.BoxDecoration(color: PdfColors.indigo700),
            headerAlignment: pw.Alignment.center,
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.center,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              5: pw.Alignment.centerRight,
            },
            cellPadding:
            const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            oddRowDecoration:
            const pw.BoxDecoration(color: PdfColors.indigo50),
          ),
          pw.SizedBox(height: 24),
        ]);
      }
    }

    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final String libellePeriode = periode == 'today'
        ? 'JOURNALIER'
        : (periode == 'month' ? 'MENSUEL' : 'ANNUEL');
    final String detailPeriode = periode == 'today'
        ? 'Journée du ${two(now.day)}/${two(now.month)}/${now.year}'
        : (periode == 'month'
        ? (moisSel != null
        ? 'Mois de ${_libelleMoisCalendrier(moisSel)}'
        : 'Mois de ${_moisCalendrier[now.month - 1]} ${now.year}')
        : 'Année scolaire $currentYear');

    String title = "RAPPORT $libellePeriode — AUTRES FRAIS DE PAIEMENT";
    if (modeFusion) {
      final String nomType = groupe != null
          ? groupe.nom
          : (paiements.isNotEmpty
          ? paiements.first.autreFraisNom
          : (paiementsAnnee.isNotEmpty
          ? paiementsAnnee.first.autreFraisNom
          : ''));
      if (nomType.isNotEmpty) title += " : $nomType";
    } else {
      title += " (TOUS TYPES CONFONDUS)";
    }
    if (sectionFilter != null) title += " - $sectionFilter";
    if (classFilter != null) title += " - $classFilter";

    final headers = [
      'ID', 'Nom Complet', 'Section', 'Classe', 'Type de Frais', 'Tranche',
      'Montant (FC)', 'Date de Paiement',
    ];

    final columnWidths =
    _buildColumnWidths([0.6, 2.0, 1.0, 1.1, 1.4, 1.8, 1.0, 1.3]);
    final double cellFontSize = _tableCellFontSize(headers.length);
    final double headerFontSize = _tableHeaderFontSize(headers.length);

    final AutreFraisGroupe? grp = groupe;
    final String numeroDetail = aDesTranches ? "4" : "3";

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) => [
          ..._buildCenteredReportHeader(
            title: title,
            subtitle: detailPeriode,
          ),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.indigo50,
              border: pw.Border.all(color: PdfColors.indigo200, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "Total Collecté (ce rapport) : ${total.toStringAsFixed(0)} FC",
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.indigo900,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  "Nombre de paiements : ${rows.length}",
                  style: const pw.TextStyle(fontSize: 11),
                ),
                if (modeFusion) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    "Élèves concernés : $totalConcernes  |  "
                        "Ont tout payé : $totalSoldes  |  "
                        "Paiement partiel : $totalPartiels  |  "
                        "Pas encore payé : "
                        "${totalConcernes - totalSoldes - totalPartiels < 0 ? 0 : totalConcernes - totalSoldes - totalPartiels}",
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ],
                if (grp != null) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    grp.montantMin == grp.montantMax
                        ? "Montant du frais : ${formatMontant(grp.montantMin)} FC"
                        : "Montants du frais selon la section/classe : de "
                        "${formatMontant(grp.montantMin)} FC à "
                        "${formatMontant(grp.montantMax)} FC",
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ],
                if (grp != null && grp.ids.length > 1) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    "Ce rapport fusionne ${grp.ids.length} configurations "
                        "portant le même nom en un seul type de frais.",
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontStyle: pw.FontStyle.italic,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
                if (aDesTranches) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    "Ce frais est payé par tranches : chaque paiement "
                        "correspond à une tranche (voir le récapitulatif par "
                        "tranche et la colonne « Tranche »).",
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontStyle: pw.FontStyle.italic,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          ..._buildStudentCountSection(
            elevesDistincts.values.toList(),
            label: "ont payé au moins un frais de ce rapport",
          ),
          pw.SizedBox(height: 16),
          ...recapWidgets,
          pw.Text(
            modeFusion
                ? "$numeroDetail. DÉTAIL DES PAIEMENTS (par section, puis par classe)"
                : "DÉTAIL DES PAIEMENTS",
            style:
            pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          if (rows.isEmpty)
            pw.Text(
              "Aucun paiement enregistré pour ce filtre sur cette période.",
              style:
              const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: rows,
              columnWidths: columnWidths,
              headerStyle: pw.TextStyle(
                  fontSize: headerFontSize,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white),
              headerDecoration:
              const pw.BoxDecoration(color: PdfColors.indigo),
              cellStyle: pw.TextStyle(fontSize: cellFontSize),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding:
              const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              oddRowDecoration:
              const pw.BoxDecoration(color: PdfColors.indigo50),
            ),
          pw.SizedBox(height: 30),
          pw.Text(
            "RÉPARTITION GLOBALE PAR ADMINISTRATION (AUTRES FRAIS)",
            style:
            pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          if (autresFraisAdministrations.isEmpty)
            pw.Text(
              "Aucune administration configurée pour les Autres Frais.",
              style:
              const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            )
          else if (total == 0)
            pw.Text(
              "Aucun montant à répartir pour ce filtre.",
              style:
              const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            )
          else
            ...adminDistribution.entries.map(
                  (entry) => pw.Text(
                "${entry.key} : ${entry.value.toStringAsFixed(0)} FC "
                    "(${autresFraisAdministrations.firstWhere((a) => a.nom == entry.key).pourcentage.toStringAsFixed(0)}%)",
              ),
            ),
          ..._buildSignatureSection(city),
        ],
      ),
    );

    // ⚡ CORRECTION — on ajoute le nom du type de frais au nom du fichier.
    //  - un frais précis (ou un groupe de frais du même nom) -> son nom ;
    //  - "tous types confondus" -> "Tous_types".
    // Résultat : un type de frais différent donne un NOUVEAU fichier, alors
    // que le même type (même période, même jour) met simplement à jour le
    // fichier existant.
    final String nomTypePourFichier = modeFusion
        ? (grp != null
        ? grp.nom
        : (paiementsAnnee.isNotEmpty
        ? paiementsAnnee.first.autreFraisNom
        : 'Frais'))
        : 'Tous_types';
    final String filenameAvecType =
        '${filename}_${_nomFichierSur(nomTypePourFichier)}';

    return await _savePdf(pdf, filenameAvecType, "autres_frais_$periode");
  }

  Future<Map<String, dynamic>> _savePdf(
      pw.Document pdf, String filename, String reportType) async {
    try {
      final bytes     = await pdf.save();
      final directory = await getDownloadsDirectory();
      if (directory != null) {
        final fileName =
            '${filename}_${reportType}_${DateTime.now().toString().split(' ')[0]}.pdf';
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(bytes);
        await OpenFile.open(file.path);
        return {'success': true, 'path': file.path};
      } else {
        final saveLocation = await getSaveLocation(
          suggestedName: '${filename}_$reportType.pdf',
          acceptedTypeGroups: [
            XTypeGroup(label: 'PDF', extensions: ['pdf'])
          ],
        );
        if (saveLocation != null) {
          final file = File(saveLocation.path);
          await file.writeAsBytes(bytes);
          await OpenFile.open(file.path);
          return {'success': true, 'path': file.path};
        }
        return {'success': false, 'error': 'Enregistrement annulé.'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}